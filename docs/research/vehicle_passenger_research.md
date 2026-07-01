# Jackie as a PASSENGER in V's car — feasibility & recipe

Research for JackieLives, patch 2.x (CET/Lua + AMM). Mirror of the already-solved "Jackie drives"
problem (`vehicle_arrival_research.md`). API verified against AMM's shipping source
(`MaximiliumM/appearancemenumod`, `Modules/scan.lua` + `util.lua`), the existing JackieVehicleTest
recipe, and the shipped "The Passenger" mod.

## Verdict: **EASY–MODERATE** (leaning Easy)

This is **more feasible than making Jackie drive**, because the whole hard part — autonomous vehicle
AI — is gone. V drives; Jackie just needs to be *mounted into a passenger seat and stay there*. That
is a solved, shipped capability:

- **AMM already does exactly this.** Its "Assign Seats" feature mounts any spawned NPC into any
  vehicle seat (`seat_front_right` / `seat_back_left` / `seat_back_right`) using the identical
  `AIMountCommand` + `MountEventData` recipe our `mountJackie()` already uses — only the `slotName`
  changes. Source: `scan.lua → Scan:AssignSeats` (lines 708–735).
- **"The Passenger" (Nexus 10731)** is a popular shipped mod that spawns Johnny into the front-right
  seat *while V is actively driving around Night City*, and he rides along persistently — proof that
  an engine-mounted NPC survives normal player driving, camera changes, and streaming. It only
  despawns him on purpose (combat, exiting the car, or conflicting quests).
  (https://www.nexusmods.com/cyberpunk2077/mods/10731)

So the mechanism is proven twice over. The only real work is glue: grab V's current vehicle handle
and mount Jackie into a free passenger seat.

## Recommended approach: **reuse the mount recipe you already have, targeting V's own vehicle**

Do **not** write anything custom. `mountJackie()` in `JackieVehicleTest/init.lua` is already 95%
there — it *is* AMM's `AssignSeats` recipe. Two changes:

1. Pass `seat = "seat_front_right"` instead of `"seat_front_left"`.
2. Use **V's currently-mounted vehicle** as the mount parent instead of a spawned bike.

No runtime AMM dependency is required — the recipe is self-contained. (You *can* route through AMM if
Jackie is an AMM-spawned companion, but it's the same API underneath.)

## Seat-slot reference (verified from AMM `scan.lua`)

AMM's canonical seat table (`Scan.possibleSeats`, lines 52–57):

| Slot cname | enum | Position |
|---|---|---|
| `seat_front_left`  | 0 | **Driver** (this is V when V drives) |
| `seat_front_right` | 1 | Front passenger ← **use this for Jackie** |
| `seat_back_left`   | 2 | Rear-left (4-seat vehicles only) |
| `seat_back_right`  | 3 | Rear-right (4-seat vehicles only) |

**Seats vary by vehicle.** A 2-seat sports car has only `seat_front_left` + `seat_front_right`;
4-seat cars add the two back seats. Some vehicles are quirky (AMM even hard-codes a fix for Claire's
truck). **Always enumerate at runtime** rather than assuming — AMM uses the vehicle-component
`HasSlot` query:

```lua
-- Does this vehicle have a given seat? (AMM's exact call, scan.lua:774)
local function hasSeat(vehicle, cname)
  return Game['VehicleComponent::HasSlot;GameInstanceVehicleObjectCName'](vehicle, CName.new(cname))
end

-- Enumerate this vehicle's passenger seats (skip the driver seat V occupies)
local function freePassengerSeats(vehicle)
  local out = {}
  for _, c in ipairs({ "seat_front_right", "seat_back_left", "seat_back_right" }) do
    if hasSeat(vehicle, c) then out[#out+1] = c end
  end
  return out   -- pick out[1] (front passenger preferred)
end
```

## Getting V's current vehicle (verified from AMM `util.lua:1072`)

```lua
-- The vehicle V is currently mounted in (nil if on foot). AMM's exact idiom.
local function playerVehicle()
  local qm = Game.GetPlayer():GetQuickSlotsManager()
  return qm and qm:GetVehicleObject() or nil   -- returns the vehicle GameObject handle
end
```

## The passenger mount — adapted from `mountJackie()`

Same recipe, front-right seat, into V's own car:

```lua
-- Mount Jackie into V's CURRENT vehicle as front passenger.
-- Reuses the exact AIMountCommand recipe from JackieVehicleTest/mountJackie + AMM Scan:AssignSeats.
local function seatJackieInPlayerCar()
  local jh  = V.jackie.handle
  local veh = playerVehicle()
  if not jh  then log("No Jackie handle."); return end
  if not veh then log("V is not in a vehicle."); return end

  local seats = freePassengerSeats(veh)
  local seat  = seats[1]                       -- front passenger if present
  if not seat then log("No free passenger seat on this vehicle."); return end

  local ok, err = pcall(function()
    local cmd = NewObject('AIMountCommand')     -- AMM uses the bare name here (scan.lua:709)
    local md  = MountEventData.new()
    md.mountParentEntityId = veh:GetEntityID()
    md.isInstant = false                        -- false = play get-in anim; true = teleport (see note)
    md.setEntityVisibleWhenMountFinish = true
    md.removePitchRollRotationOnDismount = false
    md.ignoreHLS = false
    md.mountEventOptions = NewObject('handle:gameMountEventOptions')
    md.mountEventOptions.silentUnmount     = false
    md.mountEventOptions.entityID          = veh:GetEntityID()
    md.mountEventOptions.alive             = true
    md.mountEventOptions.occupiedByNeutral = true
    md.slotName = seat                          -- "seat_front_right"
    cmd.mountData = md
    cmd = cmd:Copy()
    jh:GetAIControllerComponent():SendCommand(cmd)
  end)
  log("Seat Jackie ("..tostring(seat)..") -> "..(ok and "sent." or ("FAILED: "..tostring(err))))
end
```

Unmount is the existing `unmountJackie()` with `slotName = "seat_front_right"` (or track which seat
was used).

## Does he persist while V drives? — Yes

- Once mounted, Jackie is a genuine engine-level occupant of the vehicle, not a follow-AI target. He
  moves with the car, no per-frame re-issue needed. "The Passenger" demonstrates exactly this across
  free-roam driving.
- **Known despawn triggers to expect** (from The Passenger's behavior notes): entering **combat**, V
  **exiting** the vehicle, and **quests/activities that spawn their own passenger** (Panam/Kerry
  drives etc.) — these mods proactively unmount their NPC to avoid a two-passenger clash. Plan the
  same: unmount Jackie cleanly on combat / vehicle-exit and suppress him during scripted-passenger
  scenes.
- **Streaming:** a DES-spawned NPC (current spawn path) with `persistSpawn=false` can be culled if it
  leaves the streamed bubble — but a mounted passenger travels *with* V, so it stays inside the
  bubble by construction. Low risk. If culling appears, set `persistSpawn=true`/`alwaysSpawned=true`
  on the spawn spec.

## Existing solutions to lean on (reuse-first, per project rules)

| Mod / system | Technique | Reuse value |
|---|---|---|
| **AMM "Assign Seats"** (`scan.lua`) | `AIMountCommand`+`MountEventData`, `slotName=seat_front_right`, `isInstant=true` | **This is our recipe.** Same code we already run. If Jackie is an AMM companion, AMM can seat him directly. |
| **The Passenger** (Nexus 10731) | Spawns Johnny into `seat_front_right` while driving; redscript + CET; auto-despawn on combat/exit/conflicting quests | **Behavioral blueprint** for persistence + the despawn-trigger list. Not a dependency, but copy its rules. |
| **Blowout Jobs – Taxi Service** (Nexus 30991) | Passenger NPC rides in V's car, talks, walks off at destination | Confirms full ride-along loop (enter → ride → exit) is robust. |
| **Night City Allies / Companions of Night City** | Companion framework; "drive you around" | Reference for companion-in-vehicle handling and known conflicts. |

**Important nuance on AMM:** AMM does **not** automatically put on-foot followers into V's car as
passengers. On foot, AMM companions use a follow/warp-to-catch-up behavior; getting them *into* a seat
is the manual "Assign Seats" action (scan vehicle → pick NPC + seat → mount). So we can't just "turn
on AMM and he rides along" — but we *can* fire the identical mount call ourselves, which is trivial.
AMM's UI even hides its Assign-Seats button while you're *in* the vehicle (`scan.lua:470`, a UX
choice), which is why we call the mount directly rather than through AMM's menu.

## Entering / exiting animation

- `MountEventData.isInstant` controls it. `false` → the NPC plays a **proper open-door-and-climb-in
  animation** (immersive) — but it needs a walkable path to the door, so it works best when **the car
  is stopped** (e.g. Jackie gets in before you drive off, like a real "hop in, choom").
- `true` → **instant teleport** into the seat (what AMM's Assign-Seats uses, `scan.lua:689`).
  Safer/robust while the car is already moving, but less immersive.
- **Recommendation:** for the JackieLives flow, have Jackie get in **while stopped** with
  `isInstant=false` for the nice animation; fall back to `isInstant=true` if he ever needs to be
  seated mid-drive.

## Smallest viable CET test (prove it in ~10 min)

Add to JackieVehicleTest (spawn + the mount recipe already exist):

1. Spawn Jackie near V (existing button).
2. **Get in your own car and start driving** (or just sit in it).
3. New button **"Seat Jackie as passenger"** → calls `seatJackieInPlayerCar()` above.
4. Watch: does he appear in the right-hand seat? Then **drive around** — does he stay seated through
   turns, camera swaps, and a district transition?
5. Button **"Unmount passenger"** (existing unmount, `seat_front_right`) → does he get out cleanly?

If step 3 seats him and step 4 keeps him seated, the feature is proven and can move into JackieLives.

## Top risks

1. **Seat availability / 2-seaters.** If V's car has no free passenger seat (2-seater already full, or
   an odd vehicle), the mount silently no-ops. Mitigate with the runtime `HasSlot` enumeration above
   and a "no seat" message. Test on both a 2-seat and a 4-seat vehicle.
2. **Despawn/occupancy clashes during scripted content.** Quests that seat their own passenger, plus
   combat and vehicle-exit, will conflict. Follow The Passenger's pattern: unmount + suppress Jackie
   during those states rather than fighting the engine.
3. **DES-spawned NPC not adopted as a "clean" passenger.** A raw DynamicEntitySystem NPC should mount
   fine (AMM's do), but if you hit attitude/AI oddities (Jackie reacting instead of riding), set him
   friendly (existing `setFriendly`) and consider routing through AMM's companion role so he's treated
   as an ally, not a random NPC — same as the on-foot path.

## Sources

- AMM source (recipe + seat names): `MaximiliumM/appearancemenumod` → `Modules/scan.lua`
  (`Scan.possibleSeats` L52–57, `Scan:AssignSeats` L708–735, `Scan:GetVehicleSeats`/`HasSlot`
  L762–780), `Modules/util.lua` (`Util:GetMountedVehicleTarget` L1072 →
  `GetQuickSlotsManager():GetVehicleObject()`). https://github.com/MaximiliumM/appearancemenumod
- "The Passenger" (Johnny rides shotgun while driving; persistence + despawn triggers):
  https://www.nexusmods.com/cyberpunk2077/mods/10731 and settings addon
  https://www.nexusmods.com/cyberpunk2077/mods/18380
- Blowout Jobs – Taxi Service (passenger ride-along loop):
  https://www.nexusmods.com/cyberpunk2077/mods/30991
- Night City Allies (companion-in-vehicle, conflict notes):
  https://www.nexusmods.com/cyberpunk2077/mods/27625
- Local: `docs/research/vehicle_arrival_research.md`, `mod/JackieVehicleTest/init.lua` (`mountJackie`).
