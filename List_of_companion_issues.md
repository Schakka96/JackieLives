# List of Companion Issues — backlog & session plan
Captured 2026-06-23.

---

## Session 1 — Companion persistence & "never get lost" (HARDEST — do first)

> ✅ **DONE in v0.72 (2026-07-01), awaiting in-game test.** Persisted the INTENT via the per-save game
> fact `jackielives_companion` — chose this over the txt-file option (#1 below) because game facts live
> inside the save slot, so they're per-save correct and need no stale-restore guard. `companionPersistTick`
> (init.lua onUpdate) re-spawns + re-promotes Jackie at V when the fact says "companion" but his body is
> gone (fresh load OR a load-screen fast-travel that culled the entity). Covers all three issues below.
> Tunables in `Config.persist`. The companion *timer* is intentionally NOT persisted yet (re-arms fresh on
> reload). Bike-vs-foot default (open decision below) is still open.

Treat "is companion" as **authoritative state** that survives save/load, fast-travel, and V leaving
the map. This is the heaviest, riskiest cluster and several other issues depend on it.

**Issues:**
- **Save-file leak (root cause confirmed):** companion/follower status is NOT saved — neither manual
  nor auto save persists it. On reload, Jackie is simply gone.
- **Fast-travel breaks him / he gets lost.** When he's a companion and V fast-travels or leaves the
  map temporarily (not dismissed, not expired), the mod must stay aware he's a companion and
  re-spawn him nearby if necessary. (fixed as of v0.7)
- **Autosave-while-companion** is the same path as the above — fixing persistence fixes this too. (in progress)

**Approach (feasibility: YES, the right way):**
- Do **not** try to persist the entity itself — runtime-spawned NPCs aren't serialized and CET Lua
  state is wiped on load. That's the hard/unreliable path and it's also what fights us on fast-travel.
- Instead **persist the intent**, not the body: a small saved state = `isCompanion` flag + remaining
  companion timer + dinner/cooldown state. On load / fast-travel / return-to-map, detect the flag and
  **re-spawn + re-promote** Jackie next to V. This is the same mechanism as the rescue-spawn already
  added this session (see init.lua deadline handler) and the "respawn if lost" requirement.
- **Storage, two options (ship #1 first):**
  1. **CET state file** (`io.write` a small JSON/Lua table). Easy, fully Claude-drivable. Caveat:
     global, not per-save-slot — loading an OLD save where Jackie wasn't with you would wrongly
     restore him. Mitigate with a sanity guard (only restore if recent / V in sane state).
  2. **redscript persistent field** — state rides inside the actual save, per-slot correct. More work
     (small redscript persistence module). Do only if the stale-restore case actually bites.
- **Open decision (parked here):** default arrival = **bike** is now set in config, but bike arrival
  was historically flagged unreliable (motorcycle AI). Now that arrival robustness is being worked,
  confirm bike-default holds up or revert to foot.

---

## Session 2 — Departure / walk-away behavior (state-machine rework) (work in progress for v0.71)

One coherent rework of the dismiss/expiry walk-off (`leavingTick`, `Config.dismiss`,
`Config.companion`).

**Issues:**
- Walk away from **V's CURRENT coords**, not the coords at the moment of dismissal/timeout — so he
  keeps walking if V follows him (currently he targets a fixed point).
- When his timer expires and he's walking away, if V talks to him about **dinner** he should **stop
  and look at her** (interrupt the walk-off).
- During the walk-away stage the **only** dialogue options should be the **dinner invite** and
  **"See ya later Jackie. Take care."** The convo then resolves to either: follow V for dinner, OR
  resume the walk-away state.
- New issue unlocked after v0.7: When Jackie follows V after fast travel he becomes bugged out. 
  He despawns and respawns when V looks at him, this happens only after fast travel. What could cause this?

**Approach:**
- `leavingTick` should re-issue the move command relative to V's live position each tick (offset
  direction away from V) instead of a one-time target point.
- Add a "walking-away" sub-state to the dialogue gate so the talk menu swaps to the restricted
  2-option set while `JL.leaving.phase` is active; selecting dinner cancels `leaving` and routes into
  the dinner flow; selecting the sign-off lets the walk-off continue.
- "Stop and look at her" = halt the move command + face-V on dialogue start.

---

## Session 3 — Dinner pathing & venue safety

Both are movement / coordinate work.

**Issues:**
- On the way to dinner, Jackie should walk **closer to V, slightly ahead / right beside her** (not
  trailing). Doable coordinate-wise via a follow-target offset.
- **Venue interiors break the game** (e.g. Lizzie's): he tries to enter the interior and it breaks.
  Need to keep his seat/target at a safe exterior spot or block interior pathing.

**Approach:**
- Closer/abreast follow: replace the trailing follow distance during the dinner walk with a target
  offset to V's side/front (compute from V's forward vector + a small right-offset).
- Venue safety: confirm whether the break is interior-streaming / door-transition related. Simplest
  fix is to ensure dinner seat coords are all exterior-reachable and never trigger an interior load;
  if a venue must be interior, gate it out of the picker until proven stable.

---

## Session 4 — Sitting coords: persistence + live in-game adjust tool

**Issues:**
- The in-game slider (used at Lizzie's) prints new sit coords to Lua, but on **reload the mod uses
  OLD coords** — a save/write-back step is missing.
- Make the tool actually **persist and hot-update** the sit position in-game.

**Approach:**
- The slider currently logs values but doesn't write them back to the config/state that placement
  reads on load. Add a write-back (to the CET state file from Session 1, or a dedicated coords file)
  and make the re-seat path read the live value, so adjustments survive a reload and apply
  immediately.

---

## Session 5 — Dialogue & subtitle polish (LIGHTEST — mostly data edits)

**Issues:**
- **Sticky subtitles** — ✅ **FIXED in v0.80 (2026-07-01), awaiting in-game test.** Root cause: cleanup
  was per-code-path (`hideSubtitle` on each branch end) and the native band doesn't reliably auto-expire
  on this build, so any end path that skipped the hide stuck. The prior one-off timer
  (`leavingTick.subClearAt`) only covered ONE path. New fix = a universal `subtitleWatchdogTick`
  (onUpdate): every line records a `dueAt`; if a line outlives it while NO conversation owns the band, it
  force-clears — so no path can leak. Plus a new `Branch.finish()` authoritative close tool. See TODO v0.80.
- **"Catch you later, hermano" / "Catch you later" should END the conversation** — no trailing
  `(Leave)` menu and no `(close)` option after it; it should just close itself. (Multiple trees have
  a `bye` node ending in `{ text = "(Leave)", to = nil }` — these need an auto-close terminal.)
- **New Lizzie's-entrance conversation** (when Jackie idles at the spot near the entrance): V gets
  only ONE option — *"Jackie what you doing here??"* — and he replies with one of the 2
  "don't come here often" lines, followed by a laugh right after.

**Approach:**
- Subtitle wipe: find the current wipe path (search for the subtitle push/clear in init.lua), confirm
  whether the timer is being cancelled/overwritten by a later push, and use a robust clear that can't
  be left dangling (e.g. clear on a guaranteed tick, not only on next-line).
- Auto-close terminal: add a node/choice convention that closes the dialogue with no menu when
  `to = nil` AND flagged terminal, instead of showing `(Leave)`.
- Lizzie's-entrance tree: add a location-specific tree keyed to his Lizzie's-entrance spot with the
  single V option + the 2-line `jackiePool` + a follow-on laugh (sequence a laugh WWise event after
  the spoken line).

---

## Done this session (config tweaks — DEPLOY + in-game test still needed)

- **Phone unavailability reduced to 4h/night = 02:00–06:00** (`Config.secret.startHour 0 → 2`).
- **Default arrival method = bike** (`Config.call.arrivalMethod "foot" → "bike"`); CET window reads
  this live so it defaults to bike too. (Verify `JL.disableVehicleArrivals` doesn't default on.)
- **Bike stuck failsafe more lenient:** `Config.vehicle.stuckSustain 8 → 10` REAL seconds (covers a
  7s+ traffic light). `stuckGrace` and the slowDownDistance suppression unchanged.
- **Arrival spawn delay kept at 2s** (`vehicleSpawnDelay = 2.0`).
- **Rescue-spawn on stuck-arrival last resort (init.lua deadline handler):** the `maxSeconds` (120s)
  safety deadline used to call `promoteToCompanion`, which silently no-ops if there's no Jackie
  handle (spawn failed / body lost) → "he never spawns." Now: if a handle exists, force handoff as
  before; if NOT, despawn orphans, reset state, and **rescue-spawn a fresh companion at V** (main
  tick auto-promotes). Watch console for `rescue-spawn at V`.
  - **Still to verify in-game:** is the handle actually nil when he "never spawns," or is he
    alive-but-stuck-MOUNTED (catch-up teleport can't move a mounted NPC)? If the latter, add a
    force-dismount-then-teleport to the `resolveJackieHandle()` branch too.
