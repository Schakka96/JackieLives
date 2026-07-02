# TODO — Jackie Lives mod

_Update after every major change. See `docs/DESIGN.md` for rationale, `docs/SETUP.md` for install steps._

> 📋 **Companion backlog:** `List_of_companion_issues.md` was RESOLVED + MERGED into this file on
> 2026-07-01 (v0.83) and deleted (git history keeps it). Done items: sticky subtitles (v0.80), no-(Leave)
> auto-close (v0.81), fast-travel persistence/respawn (v0.72/v0.79/v0.82). The still-open items live in
> **"📋 Companion backlog (merged 2026-07-01)"** below, next to the START-HERE bug list.

### 🆕 Added 2026-07-01 (research + new test mod)
- **Jackie as PASSENGER in V's car** — feasibility researched → `docs/research/vehicle_passenger_research.md`.
  Verdict: **Easy–Moderate** (easier than the driver case — no vehicle AI). Same `AIMountCommand`+
  `MountEventData` recipe as `JackieVehicleTest/mountJackie()`, just `slotName="seat_front_right"` into
  V's own car (`GetPlayer():GetQuickSlotsManager():GetVehicleObject()`). Reuse AMM Assign-Seats / copy
  "The Passenger" (Nexus 10731) persistence rules.
  - **IMPLEMENTED (prove-first)** as STEP 7 in `JackieVehicleTest`: `seatJackieInPlayerCar()` +
    `unmountPassenger()` + `playerVehicle()`/`freePassengerSeat()` (runtime `VehicleComponent::HasSlot`
    seat enumeration). Buttons "7a) Seat Jackie as passenger" / "7b) Unmount passenger", instant-seat
    toggle, and hotkeys. PROBE now also reports QuickSlotsManager / HasSlot / current-vehicle.
  - `- [ ] TEST:` deploy `.\deploy_probe.ps1 -ModName JackieVehicleTest`, spawn Jackie (1b), get in a
    car, press 7a → does he appear in the passenger seat? Drive around → does he stay seated through
    turns / camera / a district change? 7b → clean exit? Test a 2-seater AND a 4-seater.
  - Once proven, port into JackieLives as a summon option (mind the 200-locals cap → new module or
    inside an existing function).
- **Jackie body-animation library builder** — new standalone `mod/JackieAnimTest/`. Random/next/replay
  buttons play an AMM `Poses` animation on the looked-at Jackie, print `[JKAnim]` name to console, and
  "Save to library" appends good ones to `jackie_anim_library.txt`. Drives AMM.Poses:GetAllAnimations()
  + PlayAnimationOnTarget (workspot system). `- [ ] TEST:` deploy via
  `.\deploy_probe.ps1 -ModName JackieAnimTest`, confirm anims play + names log + saves land.

### 🐞 START HERE next session (updated 2026-07-01, end of session) — NEXT SESSION = BUG-FIXING SPRINT
Antonia: "We have a ton of bugs on our hands. For the next session we have to start fixing those."
**v0.78 is DEPLOYED + PUSHED (tag v0.78).** Session 2026-07-01 (dismiss-despawn hunt) recap:
- **Root cause of the dismiss "instant despawn" NAILED** (bug 2d): game 2.31 teleports a just-`OnRoleCleared`
  puppet on its next `AIMoveToCommand`; the walk-off code was unchanged since v0.36. Not idle-departures/keep-close.
- **Fix shipped, needs test** (bug 2e): walk-off now uses `jlRetreatFollow` (FollowTarget to a large distance),
  no role-clear. **← first thing to verify next session** (watch `jackie_debug.log`).
- **Diagnostics added:** `log()` now also writes `mods/JackieLives/jackie_debug.log` (fresh each load);
  `jlDumpState()` + "Dump state (console)" CET button. Mouth flaps FIXED (bug 4). Follow gap set to 1.5 m.
- **v0.73 keep-close-cancel fix was tried & reverted** (didn't help); persist still OFF (bug 1, crashes).
- **Still open:** fast-travel despawn/respawn flicker (catch-up vs culling, bug 2/2c) + talk-then-dismiss CRASH
  (stale handle) + arrivals "spawns at V" rescue path. See bugs below.
What's DONE vs what's BROKEN:

**✅ Working now (v0.75):**
- **Tutorial popup FIXED.** All 5 probe variants rendered the same lower-left card, so the culprit was the
  `SignalVariant` call throwing (it made the whole push report failure → blue-band fallback). Baked the
  clean version into `retrieval.lua` `tutorialPopup()` — typed `ToVariant`, **no SignalVariant** (the
  popupManager's DELAYED listener fires on `SetVariant` alone). **Probe fully removed** (`jlPopupProbe` +
  window header gone).
- **Both shard messages written** (`retrieval.lua` Config): Vik's reveal (`tipText`, title "Viktor
  Vektor") + Jackie's Rocky Ridge note (`shardLines`, title "Shard — Jackie Welles"). In-character;
  tweak the prose freely.

**🐞 KNOWN BUGS — fix these next session (highest first):**
1. **CRASH: companion persistence across a load.** The v0.72 auto-respawn (`companionPersistTick` →
   `respawnCompanionAtV`) **crashes the game on load**. → **Mitigated for now: `Config.persist.enabled =
   false`** so the build is stable (fact-tracking still runs; only auto-bring-him-back is off). FIX:
   almost certainly `ammSpawn` firing too early / into a not-fully-streamed world, or an AMM call before
   AMM re-inits post-load. Try a much longer/whole-frame-safe startup gate, verify AMM-ready + player
   fully in-world before spawning, or switch to a MANUAL "he's back" trigger. See `config.lua`
   `Config.persist` warning + init.lua `companionPersistTick`/`respawnCompanionAtV`.
2. **Jackie despawns/respawns when V LOOKS AT him after a fast-travel.** Reported again; it's in
   `List_of_companion_issues.md` (Session 1 cluster / catch-up). May be `catchUpTick`'s teleport fighting
   the look-at/talk system, or the (now-disabled) persist respawn — re-check whether disabling persist
   (#1) changed it. Reproduce: be a companion → fast-travel → look straight at Jackie.
   - **2f. ✅ FIXED (2026-07-01, v0.79 — CONFIRMED in-game by Antonia).** The "`CatchUp: was 1994 m -> teleported
     to her side` but he's still 2 km back, and travelling back doesn't fix it" case. `catchUpTick` logged
     success without verifying the `AITeleportCommand` landed; across a district-scale FT his body is stranded
     unstreamed so the teleport no-ops. Catch-up now escalates to `respawnCompanionAtV` beyond
     `Config.catchUp.respawnDistance` (150 m) or after a teleport fails to close the gap. See v0.79 section below.
     **v0.82** then removed the visible pop-in / wall-clip on that respawn (hide 2 s + collision-off 4 s; see v0.82).
   - **2e. FIX ATTEMPT SHIPPED (2026-07-01, v0.78) — AWAITING IN-GAME TEST.** Reworked the walk-off
     (`startLeaving`/`leavingTick`) per 2d: **no more `OnRoleCleared` + far `AIMoveToCommand`** (the teleport
     trigger). New global `jlRetreatFollow(h, mv, dist)` issues an `AIFollowTargetCommand` with a LARGE
     `desiredDistance` (despawnDistance+4) and `matchSpeed=false`, re-issued every 1.5 s by `leavingTick`, so
     the follow AI walks him AWAY to ~30 m (then despawn). He stays a companion during the stroll (role not
     cleared) so nothing snaps him. `startLeaving` logs a `jlDumpState("startLeaving")` baseline and
     `leavingTick` logs `walking off... N m` each re-issue.
     - [ ] **TEST:** summon → "Head home, Jackie." → he should **walk away and get distance**, N climbing in
       `jackie_debug.log`, then `despawned (reached distance…)`. If **N stays flat** (~1.5 m), the follow AI
       won't open a gap → tell Claude; fallback = keep role-clear but drive movement a non-teleporting way
       (e.g. short re-issued moves, or an AITeleport-free patrol). Grab `mods/JackieLives/jackie_debug.log`.
   - **2d. ROOT CAUSE CONFIRMED (2026-07-01, v0.77).** The dismiss log (`console_log_dismiss_1.txt`) +
     history dig settle it: `startLeaving`/`leavingTick`/`awayPoint`/`sendMoveToPoint` are **byte-identical
     to v0.36** (where the walk-off was born; v0.30 had none), so the departure CODE never changed. The
     `startLeaving` dumps prove `OnRoleCleared` does NOT move him (PRE and POST both `dist=1.5`). But by the
     next `leavingTick` he's at `(-1540.2,1247.3)` = **exactly `awayPoint` (V + despawnDistance+8 = 38 m)** →
     the `AIMoveToCommand` **teleported** him to the target instead of walking, so he instantly hit the ≥30 m
     "reached distance" despawn. The ONLY thing unique to dismiss vs the (still-working) arrival walk-in /
     idle wander — both of which use the same `sendMoveToPoint` — is that dismiss **clears the companion role
     first**. So on game 2.31 a just-`OnRoleCleared` puppet's move executes as an instant teleport-to-target.
     NOT the idle-departure system, NOT a random away-point, NOT keep-close. **FIX DIRECTION:** stop relying
     on `OnRoleCleared` + far `AIMoveToCommand`. Best candidate = drive the walk-off with an
     `AIFollowTargetCommand` (target=V, `desiredDistance`=despawnDistance, `matchSpeed=false`, Walk) — the
     command type that provably WALKS on 2.31 (keep-close uses it) — so he "keeps his distance from V and
     walks off" (Antonia's remembered behaviour). RISK: if the follow AI only closes gaps (never retreats),
     he won't move → pivot to keeping the role + suppressing AMM's follow another way. Reverted the v0.76 hop
     experiment (Antonia: too clunky); walk-off code is back to the clean v0.36 baseline + diagnostics kept.
   - **2c. IN-GAME EVIDENCE (2026-07-01 test on the reverted build) + v0.76 diagnostics added:**
     - **Dismiss (fresh companion, no fast-travel):** console shows `Dismiss: Jackie walking away (despawn
       at 30m)` then INSTANTLY `Dismiss: despawned (reached d=38 m)` — but he's still at V's side. **38 =
       despawnDistance(30)+8 = the `awayPoint` target distance**, so `leavingTick` read a bogus far position
       on the very first tick (almost certainly `OnRoleCleared` invalidating/relocating the handle) and
       insta-despawned him. He never walks. → **v0.76 added:** (a) `jlDumpState()` global + a **"Dump state
       (console)"** CET button; (b) dumps in `startLeaving` PRE/POST `OnRoleCleared` (to catch a position
       jump) and at the `leavingTick` far-despawn; (c) a **`Config.dismiss.graceSeconds` (3 s) guard** so the
       "far" despawn can't fire in the first few seconds (deadline still cleans up). NEXT TEST: dismiss and
       read the PRE vs POST `dist=` — if POST jumps to ~38, `OnRoleCleared` is teleporting/culling him and
       the real fix is to stop clearing the role that way (or move him first, clear role later).
     - **Fast-travel:** with `catchUp` ON, Jackie despawns+respawns on a ~2.5 s timer (the `catchUpTick`
       teleport fighting fast-travel entity culling — NOT triggered by looking at him). With
       `catchUp.enabled=false`, he's culled and never returns (persist is off), yet `summon.active` stays
       true so the phone summon is blocked ("already with you"). → the FT-culled companion needs its handle
       validated + state cleared (or a proper re-spawn). Ties into Bug #1 (persist) + List_of_companion_issues S1.
     - **Talk-then-dismiss = CRASH.** Likely `OnRoleCleared`/method calls on a stale/dead handle (native
       crash, not pcall-catchable). The v0.76 dumps will show how far it gets before the crash.
   - **2b. DISMISS walk-away also hard-despawns him in V's face** (was the whole point of the walk-away —
     he should stroll off toward a street). **v0.73 tried & REVERTED (2026-07-01):** the theory that the
     keep-close follow (`followKeepCloseTick`) leaves a lingering `AIFollowTargetCommand` that out-prioritises
     the away move was wrong — cancelling it (`jlStopFollow` + faster `leavingTick` re-issue) did NOT help and
     may have worsened arrivals, so it was reverted (commit `5183dfe`). ⇒ the walk-away code itself is fine;
     the despawn is being forced by something ELSE. **DIAGNOSTIC (do first, cheap):** dismiss via "Head home,
     Jackie." and read the `[JackieLives]` console — the path self-identifies: `Dismiss: Jackie walking away…`
     then repeated `Dismiss: walking off… N m from V.` If **N stays ~2–3 m** he isn't moving (AMM re-follow on
     the new build / role-clear not releasing him → he hits the 30 s `maxSeconds` deadline and despawns where
     he stands). If it logs `RETURN TO POST` he went to the idle system and `scheduleTick`'s `clearIdle` may be
     insta-removing him. If it logs `Dismissed.` you hit the instant button/hotkey path, not the walk-away.
     Likely same family as #2 (a NEW per-frame relocation/removal force, or an AMM/game-2.31 companion-release
     change), NOT the walk-away logic. Toggle `Config.catchUp.enabled=false` + `Config.follow.enabled=false`
     to A/B whether the v0.66/v0.67 systems are involved.
3. **The rest of the bug pile** — go through `List_of_companion_issues.md` (Sessions 1–5) + the many older
   "awaiting test" items below; Antonia to prioritise which bugs bite most in play.
4. ✅ **FIXED (2026-07-01) — Mouth flaps** work again after reverting v0.73 (the reverted build restored
   them). No further action; leaving the notes below for reference in case they regress again.
   ~~**Mouth flaps dead — Jackie's lips don't move while a subtitle line shows** (regressed; reported
   2026-07-01). Should be an easy fix.~~ The flap is `speakJackieLine` → `startFlap(secs)` → `flapTick` →
   `applyTalkingFace` (AMM Expressions Overhaul "Talking" faces, FacialReaction **category 7**, idles
   231–266 skip 242) via `handle:GetAnimationControllerComponent():ApplyFeature("FacialReaction", …)`.
   `startFlap` is still called unconditionally (even mute — `secs` falls back to 3.0), so the trigger is
   intact. Suspects, in order: (a) **AMM Expressions Overhaul / Extra Expressions not installed** on the
   current rig → category-7 faces absent → `ApplyFeature` no-ops (the code says it degrades silently);
   (b) game 2.31 changed the `AnimFeature_FacialReaction` API / category id; (c) `dialogueTarget()` returns
   nil at line time (it shouldn't for a present companion). FIX PLAN: add a one-off debug log inside
   `applyTalkingFace` (did `anim` resolve? did `ApplyFeature` run?), confirm the expressions mod is present,
   else re-point to a facial mechanism that ships with base AMM. NOT related to the mute build (audio path
   is separate from the face feature).
- Then (once #1 is stable): finish **persisting the companion TIMER** (spec in the v0.72 section).
- Housekeeping: `getTalkTarget` + `Config.probeNativePhone` are harmless dead leftovers. `staging/` was
  **UNPARKED + synced to v0.83 for a Nexus release (2026-07-01)** — it now carries `init.lua` + `config.lua`
  + **`retrieval.lua`** (the last was MISSING while parked at v0.67; `init.lua` `require`s it, so the old zip
  would have crashed on load). Keep `staging/bin/.../mods/JackieLives/` in lockstep with `mod/JackieLives/`
  on every code change (the 3 Lua files), or write `package.ps1` to build the zip from source instead.
  ⚠️ A second Claude session commits to this SAME repo — always `git fetch` first.

### 📋 Companion backlog (merged 2026-07-01 from `List_of_companion_issues.md`, now deleted)
The old 5-session backlog file was resolved + folded in here. **Resolved:** S1 persistence (v0.72/0.79/0.82),
S5 sticky subtitles (v0.80) + no-(Leave) auto-close (v0.81), S2 walk-off-from-live-V-coords (v0.77/0.78
retreat-follow). **Still open, grouped by area:**

**🪑 Sitting positions & venues (Antonia does the coord capture; Claude wires it):**
- [ ] **FIX THE SITTING POSITIONS MANUALLY (Antonia).** Several dinner/idle seats are off (wrong spot/height/
      facing). Antonia will walk Jackie to each venue, use the in-game seat tuner to line him up, and send the
      printed coords; Claude bakes them into `Config.date.restaurants` / `Config.locations`. **Blocked on**
      the sit-coords-don't-persist bug below (the tuner's values must survive a reload to be usable).
- [ ] **Sit coords don't persist on reload (old S4).** The in-game seat slider prints new coords to Lua but
      the mod re-reads the OLD `Config` values on reload — a write-back step is missing. Add a write-back
      (CET state file or a dedicated coords file) + make the re-seat path read the live value, so tuner
      adjustments survive a reload and apply immediately. (Enables the manual fix above.)
- [ ] **Venue interiors break the game (old S3), e.g. Lizzie's.** He tries to path INTO an interior and it
      breaks. Keep every dinner seat at an exterior-reachable spot that never triggers an interior load; gate
      any must-be-interior venue out of the picker until proven stable.

**🍽️ Dinner outing polish (old S3):**
- [ ] **Walk abreast, not trailing.** On the way to dinner Jackie should walk slightly ahead / right beside V
      (offset from V's forward vector + small right offset), not behind on the long companion leash.

**🚶 Walk-off / departure (old S2 leftovers):**
- [ ] **Interrupt the walk-off for dinner.** If his timer expires and he's walking away, talking to him about
      dinner should STOP the walk-off (halt the move + face V) and route into the dinner flow; otherwise the
      sign-off lets him continue. During the walk-away the ONLY options should be the dinner invite + a
      sign-off. (Partially eased by v0.78 retreat-follow, but the "stop & accept dinner" interrupt isn't built.)

**💬 Dialogue content (old S5 leftover):**
- [ ] **Lizzie's-entrance one-liner tree.** When Jackie idles at the spot near Lizzie's entrance, V gets ONE
      option — *"Jackie, what you doin' here??"* — and he replies with one of the 2 "don't come here often"
      lines, then a laugh WWise event right after. Add as a location-specific tree keyed to that idle spot.

**🐞 NEW BUG (2026-07-01) — dinner dismiss crash → FIXED in v0.83 (interim done):**
- [x] **Dismissing Jackie WHILE SEATED at dinner crashed the game** (he didn't get up; crash after a beat).
      Cause: the seated puppet has its role cleared + is locked in a sit workspot, so `startLeaving` couldn't
      move him. **v0.83 removed the "Head home, Jackie" option during any dinner outing** (`withCompanionExtras`
      now bails when `JL.dinner.phase` is set); use the new seated **"Enough chillin', let's go"** (stands him
      up + re-follows) to end a dinner. [ ] TEST: at dinner, confirm there's NO "Head home" option and the
      game doesn't crash; ending via "let's go" works.

**🔧 Open decision (old S1):** default arrival = **bike** — confirm it holds up now that arrival is more
robust, or revert to foot (`Config.call.arrivalMethod`).

### ▶️ Older OPEN verification tasks (still awaiting in-game test)
- [ ] **TEST: Companion catch-up teleport (v0.66, NEW).** While Jackie is a SETTLED companion (arrived,
      not dismissed), **FAST-TRAVEL** away (or sprint >25 m off) and confirm he **teleports to V's side**
      within ~2 s, landing a few m beside her (NEVER on top of V). Console logs `CatchUp: Jackie was N m
      from V -> teleported to her side.` Tunables in `Config.catchUp` (distance/sustain/cooldown/placeDistance).
      - Known limit: if a load-screen fast-travel **culls his entity** (handle nil), teleport can't help →
        he's just gone. That's the heavier persist+respawn job (List_of_companion_issues.md Session 1).
- [ ] **Bug 1 follow-up — "spawns inside V" on a FAILED approach.** The catch-up teleport now always lands
      him *beside* V, but the original yank-onto-V comes from the **arrival fallbacks** (rescue-spawn at V /
      `maxSeconds` force-handoff using AMM's catch-up). NEEDS: observe whether it happens on a *normal* call
      arrival or only after he gets *stuck approaching*; then offset those fallbacks the same way (place
      beside V, not on her) and/or reduce stuck-arrivals. See diagnosis 2026-06-30.
- [ ] (prior v0.65 tasks below — all DEPLOYED in v0.65, awaiting in-game test)
- [ ] **Bike record (v0.65, top priority):** in CET → "Bike model test", click **B1/B2/B3** → report which
      spawns Jackie's real (gold) Arch + the console `READ-BACK` appearance string. Then **lock that
      record (+appearance) into the live arrival** (`spawnDynEntity` bike spawn; `Config.vehicle.bikeRecord`
      /`.bikeAppearance` exist). If none match, use the read-back ids / "Dump appearances" / a full TweakDB
      vehicle dump to find more candidates. See logbook "BIKE-RECORD HUNT".
- [ ] **Main-quest ban (v0.62):** confirm "Main quest detected" flips **YES** during a real main quest and
      stays **no** on side jobs / free-roam; that a companion Jackie then excuses himself + walks off; and
      summon/call decline. If the journal reflection never flips, revisit `isMainQuestActive()` (API/enum).
      Optional: give the main-quest exit a DEDICATED VO line (`Config.mainQuestExit`, currently the send-off line).
- [ ] **Safety dismount (v0.62):** on a bike arrival where he used to stay seated, confirm the
      `still mounted -> safety dismount` log fires and he ends up off the bike (no phantom get-off on foot).
- [x] Housekeeping: `List_of_companion_issues.md` resolved + merged into this file and deleted (v0.83).

## 🆕 v0.83 — dinner SEATED small-talk tree + dinner-dismiss crash fix (2026-07-01, awaiting in-game test)
Two conversation fixes in the dinner area (config.lua tree + small init.lua wiring).
- **Seated small-talk tree.** While Jackie is SEATED at dinner (`JL.dinner.phase == "seated"`), talking to
  him now uses a dedicated `Config.date.seatedTree` (wired via `currentTalkTree`) instead of the generic
  companion tree: casual openers (`jackiePool`) + a few **random-chance** "get it off your chest" topics —
  merc life, Night City, Arasaka, Jackie & Misty. Each topic choice carries a `chance` (new per-choice
  field, re-rolled every menu open via `openChoiceMenu`), so the options vary each time.
- **"Enough chillin', let's go" → stand up + re-follow.** A always-present sign-off runs action
  `dinner_leave`, which (after his reply line) sets `JL.dinner.leaveNow`; `dinnerTick`'s seated phase then
  runs the SAME stand-up + `promoteToCompanion` path it already used when V walks away — so he gets up and
  re-joins as companion. Clean reuse of tested code; no new movement logic.
- **Dinner-dismiss CRASH fixed.** `withCompanionExtras` now bails whenever `JL.dinner.phase` is set, so the
  "Head home, Jackie" option no longer appears during a dinner outing. Dismissing a seated (role-cleared,
  workspot-locked) puppet was the crash. End a dinner with "let's go" instead. (See the backlog NEW BUG item.)
- New dinner lines are **text-only** (no sfx yet) → fallback grunt + subtitle on the mute build; wire real
  `jl_` clips later. Zero new top-level locals; both files compile clean. Version 0.82 → **0.83**.
- [ ] **TEST:** start a dinner → once he's SEATED, talk to him → you get casual small talk + varying topic
      options (NOT the "Head home" dismiss). Pick a topic → he gives a thoughtful reply. Pick "Enough
      chillin', let's go" → he says a line, **stands up, and follows again** (no crash). Re-open a few times
      → the topic options vary. Confirm dismissing at dinner is impossible (no crash).

## 🆕 v0.82 — POLISH: no pop-in / no wall-clip on the fast-travel respawn (2026-07-01, awaiting in-game test)
**Follows v0.79 (which fixed the actual "stranded 1994 m" bug — CONFIRMED FIXED in-game by Antonia).**
**Antonia's ask:** the respawn works, but Jackie visibly POPS in before settling after a fast-travel — hide
him ~2 s, and turn his collision off ~4 s so he can't respawn into a wall.
**Fix:** `respawnCompanionAtV` now arms a settle window (`JL.settle.hideUntil`/`collideUntil`); new
`settleTick` (onUpdate, GLOBAL fn — 200-cap safe) keeps the fresh body INVISIBLE + NON-COLLIDING and
re-asserts both every frame against the live handle (which resolves a frame or two after the spawn, so a
one-shot would miss it), then reveals him at `hideSeconds` and restores collision at `collideSeconds`. Reuses
the arrival sequence's own `setVisible`/`setNpcCollision` helpers; the respawn promote path never flips
visibility so nothing fights it. Applies to BOTH respawn callers (catch-up FT + persist). Tunables in
`Config.respawnSettle` (`enabled`/`hideSeconds`=2/`collideSeconds`=4). Both files `luajit -bl` clean. 0.81 → **0.82**.
- [ ] **TEST:** be a companion → fast-travel far → he should FADE/appear in place at V (no pop beside her)
      and never end up stuck in a wall. Console still logs the v0.79 `CatchUp: ... respawning at her side.`
- Note: v0.79's escalation is what actually recovers him; this only smooths the visual. If he ever falls
      through the floor during the collision-off window, drop `collideSeconds` (collision-off is the same
      trick idle/dinner already use safely, so unlikely).

## 🆕 v0.81 — dialogue polish: no (Leave), dismiss on main node only, randomized sign-offs (2026-07-01, awaiting in-game test)
Follow-up to v0.80 (sticky-subtitle fix), all in `config.lua` + two small `init.lua` helpers.
- **No more `(Leave)` menus.** Every `bye`/`care` terminal node dropped its `{ "(Leave)", to = nil }`
  choice, so it's now a Jackie-only terminal node → `branchTick` plays his last line then **auto-closes
  the box** (via `Branch.finish`). The player never clicks a dead "(Leave)"/"(close)" button.
- **Dismiss (+ dinner invite) only on the MAIN node.** `withCompanionExtras` now injects the "Head home,
  Jackie" / dinner-invite choices ONLY on the tree's START node. If V picks a sub-branch, it just plays
  out and closes — to dismiss/invite again she re-opens the conversation (press F again). By design.
- **Randomized sign-offs.** New `textPool` field on a choice: `openChoiceMenu` picks a random line from it
  each time the menu opens (like Jackie's `jackiePool` replies shuffle). The two `everywhere`-tree
  sign-offs ("Just checkin' in…" / "Catch you later…") became 4-line pools that better set up his reply —
  left pool → his "you take it easy, rest up"; right pool → his "time we were on our way" ("We should get
  movin'." / "Let's get goin', hermano." / …). Edit the pools freely in `config.lua`.
- Zero new top-level locals; both files compile clean. Version 0.80 → **0.81**.
- [ ] **TEST:** talk to a companion/idle Jackie → pick any sign-off → he says one line and the box closes
      by itself (no "(Leave)"). Re-open a few times → the sign-off wording varies. As a companion, "Head
      home, Jackie" shows on the FIRST menu only; dive into a sub-branch and it's gone until you re-open.

## 🆕 v0.79 — FIX: fast-travel "teleported to her side" but Jackie stays 1994 m away (2026-07-01, awaiting in-game test)
**Symptom (Antonia):** after a fast-travel the console logs `CatchUp: Jackie was 1994 m from V -> teleported
to her side.` yet Jackie is NOT with V — he's stuck ~2 km back. Fast-travelling BACK to where we came from
doesn't recover him either. (Bug #2 / catch-up cluster.)
**Root cause (diagnosed from code + the console line):** `catchUpTick` fired `aiTeleport()` (an
`AITeleportCommand` through Jackie's `AIControllerComponent`) and then **logged "teleported to her side"
unconditionally — it never verified the command moved him.** A load-screen fast-travel across DISTRICTS
leaves his body stranded in an unstreamed region: the handle still resolves (that's how catch-up read
`1994 m` from `GetWorldPosition`), but his AI won't execute a teleport across that streaming gap, so the
command **silently no-ops** and he stays put. The old "known limit" guard only caught `handle == nil` (fully
culled); "handle resolves but is stranded far" slipped through. `Config.persist` (which *would* respawn him)
is both disabled AND explicitly skips whenever a live handle-with-position exists — so nothing recovered him.
**Fix (init.lua `catchUpTick` + `Config.catchUp`):** `aiTeleport` can't cross a district-scale gap, so
catch-up now ESCALATES to a **despawn + respawn-fresh-at-V** (`respawnCompanionAtV`, the same call the persist
path uses) when either (a) he's beyond `Config.catchUp.respawnDistance` (150 m — obvious FT, skip the doomed
teleport) or (b) a teleport already fired but failed to close the gap (`teleTries` reached `maxTeleTries`, i.e.
he's still far after the cooldown — self-verifying, catches stranded-but-under-150 m and any no-op). The retry
counter clears the moment he's back within range. **Why this is safe when persist-on-load isn't:** it fires
2 s+ AFTER the fast-travel with V fully streamed in-world, not during the load event — so it dodges the
`ammSpawn`-into-a-not-yet-streamed-world crash that keeps `Config.persist` off. After respawn, the existing
onUpdate promote block (`SetNPCAsCompanion` at init.lua ~4007) re-applies the follower role next frame, and
keep-close/catch-up resume. Independent of `Config.persist.enabled`, so it works with persist still off.
Zero new top-level `local`s (function-internal `tries` + `JL.catchUp.teleTries`/`Config.catchUp` fields only);
both files compile clean under the 200-local cap (`luajit -bl`). Version 0.78 → **0.79**.
- [ ] **TEST (core):** be a settled companion → **fast-travel far** (across districts). Within a few seconds
      console should log `CatchUp: Jackie stranded N m from V (teleport can't cross) -> respawning at her
      side.` and he reappears at V, follower role re-applied (`Companion role applied.`). No more "teleported"
      line that leaves him behind.
- [ ] **TEST (moderate gap):** sprint 30–100 m off (same district, no load). He should still slide over via
      the cheap teleport (`... -> teleported to her side (try 1).`), NOT respawn-pop.
- [ ] **Tunables** in `Config.catchUp`: `respawnDistance` (150), `maxTeleTries` (1), `respawnWhenStranded`
      (set false to go back to teleport-only). If the respawn ever lands him too close to V, that's the shared
      `ammSpawn`/`respawnCompanionAtV` placement (TODO bug #1 follow-up "spawns inside V") — offset it there so
      BOTH the persist and catch-up respawns benefit.

## 🆕 v0.80 — STICKY SUBTITLE fix: guaranteed cleanup tool + watchdog (2026-07-01, awaiting in-game test)
**Symptom (Antonia):** some conversation branches — *especially ones that DON'T end on a `(Leave)`
choice* — leave the bottom subtitle band stuck forever (e.g. right on "…chica" after the dinner invite).
Happens when a branch reaches its end via a path that never hit a `hideSubtitle()` call.
**Root cause (why the old one-off fix — `leavingTick.subClearAt` — didn't hold):** subtitle cleanup was
managed *per code path*. Every branch that ended a talk had to remember to call `hideSubtitle()`, and
`hideSubtitle` only clears the single last-tracked line. The native band does **not** reliably
auto-expire on this build, so ANY end path (or one-off line like an arrival greeting) that skipped the
explicit hide left the band stuck. A timer bolted onto ONE path can't cover the others.
**Fix (game-dev 101 — don't trust every exit path; enforce cleanup on a guaranteed tick):**
- **`subtitleWatchdogTick` (new, onUpdate, the real fix).** Every subtitle now records a `dueAt`
  (display time + 0.75 s grace) in `showSubtitle`. Each frame the watchdog checks: if a line is still
  showing past its `dueAt` **and nothing owns the band right now** (no `Branch.busy/open`, no
  `dlg.active`, no live call, not the leaving parting-line), it force-clears it. It is hands-off during
  any active conversation, so it can only ever wipe a genuinely orphaned line — present or FUTURE trees.
- **`Branch.finish(reason)` (new, the "stable tool" Antonia asked for).** One authoritative "conversation
  ended" call that ALWAYS closes the choice menu + native "[F] Talk" box, resets `Branch`/`bstate`, and
  wipes the subtitle together. `branchTick`'s normal talk-end path now funnels through it (call-wrap-up
  path unchanged — it must show V's farewell before hanging up). Idempotent; watchdog backs it up.
- **Bonus:** one-off lines that previously had no follow-up hide (arrival greetings, etc.) are now
  cleaned up by the watchdog too.
- Implemented with **zero new top-level locals** (global fn + `Branch`/`subtitle` table fields) — still
  loads under the 200-local cap; both files compile clean (`luajit -bl`). Version 0.79 → **0.80**.
- [ ] **TEST:** run several conversations to their end, especially branches that do NOT end on `(Leave)`
      (dinner invite → pick a venue; any tree's terminal Jackie line; an arrival greeting). In every case
      the bottom subtitle should disappear within ~1 s of the talk ending — none should stick. If one ever
      lingers, the console logs `Subtitle watchdog: cleared a dangling subtitle` when it self-heals (tell
      me which line so we can also fix its path directly). Confirm normal in-convo lines still hold on
      screen while you read the choice menu (watchdog must NOT wipe them early).

## 🆕 v0.73 — FIX: dismiss walk-away (Jackie was hard-despawning in V's face) (2026-07-01, awaiting in-game test)
**Symptom (Antonia):** picking the in-dialogue "Head home, Jackie." used to make Jackie walk off toward a
street and vanish out of sight; now he just hard-despawns right in front of V.
**Root cause (diagnosed from code):** the walk-away (`startLeaving` → `leavingTick`) is unchanged, but the
**v0.67 keep-close follow** (`followKeepCloseTick`) went live only in v0.68 (init.lua didn't load v0.66–v0.67
due to the 200-local cap) — exactly when this broke. Keep-close re-issues a **persistent**
`AIFollowTargetCommand` every ~1.5 s to hold him tight behind V. On dismiss, `OnRoleCleared` drops AMM's
companion role but does **not** cancel *our own* follow command, and on the current build a follow command
out-prioritises the away `AIMoveToCommand` — so he stayed glued to V, never reached `despawnDistance`, and the
`maxSeconds` (30 s) safety despawn fired in V's face. Supporting evidence: the **idle** walk-away
(`idleLeavingTick`, no keep-close) still works; the only two paths that `moveTo` a *keep-close* companion are
the two dismiss paths (`startLeaving`, `returnToPost`); keep-close itself only works because a follow command
beats AMM's leash — implying a plain `moveTo` cannot.
**Fix:** `sendWalkToPlayer` now returns the command handle; `followKeepCloseTick` stores it in `JL.follow.cmd`;
new global `jlStopFollow(h)` cancels it (`StopExecutingCommand`, mirroring the bike's `stopBikeVeh`, both
receivers tried + pcall-guarded). `startLeaving` and `returnToPost` call `jlStopFollow` before the away move.
Also dropped `leavingTick`'s re-issue interval from a hard-coded 1.5 s → `Config.dismiss.reissueInterval` (0.6 s)
so the away move re-asserts faster against any residual pull. Global helper (not a main-chunk local) → cap
unaffected; both files compile clean (`luajit -bl`).
- [ ] **TEST:** summon Jackie → "Head home, Jackie." → he should say his line, **walk off ~30 m and vanish out
      of sight**, not despawn at V's feet. Console should log `Dismiss: walking off... N m from V.` with N
      *increasing*, then `Dismiss: despawned (reached distance, ...)` — NOT `(deadline, ...)`.
- [ ] If he STILL hard-despawns: the console will show the deadline despawn / N not increasing. Fallbacks to try
      in order: (a) CET sliders won't help here; set `Config.follow.enabled = false` to confirm keep-close is the
      culprit; (b) if confirmed but the cancel didn't take, `StopExecutingCommand` may not exist for puppets on
      this build → tell Claude (next lever: keep him as companion during the walk-off + redirect, like dinner).

## 🆕 v0.72 — COMPANION PERSISTENCE: Jackie survives save/load + culling fast-travel (2026-07-01, awaiting in-game test)
List_of_companion_issues.md **Session 1** (the hardest cluster). Treats "is Jackie your companion" as
authoritative state that rides inside the save.
- **Storage = per-save GAME FACT `jackielives_companion`** (NOT a global file). Same mechanism the
  retrieval quest uses for its stage, so it's automatically **per-save-slot correct**: loading an old
  save where Jackie wasn't with you finds the fact unset → he is NOT wrongly restored. This sidesteps the
  stale-restore caveat that made the backlog's "CET txt-file" option (#1) risky — game facts are the
  better of the two storage options it listed, with no redscript needed.
- **Mechanism = `companionPersistTick`** (new, in onUpdate next to `catchUpTick`). While the mod is
  unlocked: if the fact says "companion" but no live Jackie body exists — a fresh load wiped the Lua
  state, OR a load-screen fast-travel **culled his entity** (the exact case `Config.catchUp` can't
  recover) — it **re-spawns + re-promotes him at V's side** via the existing `ammSpawn(1)` + promote
  path. Self-healing: it also keeps the fact in sync with reality, guards a `startupGrace` so it never
  spawns into a loading screen, rides out stream hiccups (`gapSustain`), and throttles respawns
  (`cooldown`). Skips while an arrival / dinner / walk-off state machine already owns him.
- **Flag lifecycle:** set ON at both companion-promote points (`promoteToCompanion` + the onUpdate summon
  promote); cleared at every "no longer a companion" transition (`dismissJackie`, `dismissAllJackies`,
  `leavingTick` despawn). Tunables in `Config.persist` (`enabled`/`startupGrace`/`gapSustain`/`cooldown`).
- **CET window:** new "Saved companion flag: ON/off" readout + "Clear saved flag" test button under
  Dismiss, so the persistence is observable in-game.
- **🛠 Also fixed a v0.69 REGRESSION found while doing this:** the v0.69 dead-code sweep accidentally
  deleted `jlSaveSettings`/`jlLoadSettings`/`hardReset` but left their call sites — so Esc-menu toggle
  persistence (husbando / disable-vehicle-arrivals) AND the "Go Home Jackie" recovery button had been
  silently no-op'ing since v0.69. Restored all three **as globals** (no new main-chunk locals → 200-cap
  safe). `getTalkTarget` + `Config.probeNativePhone` remain the only known harmless leftovers.
- Implemented with **zero new top-level `local`s** (globals + JL/Config table fields); all three files
  still compile clean under the 200-local cap (`luajit -bl`). Version 0.71 → **0.72**.
- [ ] **TEST (core):** summon Jackie → "Saved companion flag: ON". **Hard-save + reload** → within
      ~3 s he reappears at V's side (console `Persist: ... respawned him at V`). Dismiss him → flag goes
      **off** → reload → he stays gone.
- [ ] **TEST (fast-travel cull):** as a companion, **fast-travel** (the load-screen kind). If the FT
      culls his body, he should respawn at V within a few seconds (console `Persist: ...`). If his body
      survives, `catchUpTick` handles it as before — either way he ends up next to V.
- [ ] **TEST (regression fixes):** toggle "Husbando mode" / "Disable vehicle arrivals" in Esc→Settings,
      reload → the toggle **sticks** (was broken since v0.69). "Go Home Jackie" button actually despawns
      + resets him again.
- [ ] **TODO — persist the companion TIMER too (Antonia asked, 2026-07-01).** Right now only the
      boolean intent persists; on reload the duration clock re-arms fresh (`Config.companion.maxGameHours`),
      so a companion who was 5 h 55 m in gets a full 6 h again. Plan: game facts are int, so at the point
      we know the remaining time, store it — e.g. write `jackielives_companion_expires` as an absolute
      in-game-second stamp (`JL.summon.companionExpiresGame`) whenever it's armed/changed, and on the
      persistence respawn set `JL.summon.companionExpiresGame` from that fact instead of re-arming. Watch
      the int32 range (in-game seconds can get large on long saves — store remaining-seconds-from-now if it
      overflows). Low risk; slots straight into `companionPersistTick` + `armCompanionTimer`.

## 🆕 v0.75 — tutorial popup FIXED + both shard messages written; persistence DISABLED (crashes on load) (2026-07-01)
- **Popup fixed.** Probe result: all 5 variants gave the same lower-left window → the original failure was
  the `SignalVariant` call throwing (failing the pcall → blue-band fallback). `retrieval.lua`
  `tutorialPopup()` now does typed `ToVariant` + `SetVariant` for Popup_Settings/Popup_Data and **no
  SignalVariant** (the popupManager listener is delayed and fires on the SetVariant). Probe removed.
- **Shard text written** (`retrieval.lua`): `tipTitle`/`tipText` = Vik's reveal ("Viktor Vektor"),
  `shardTitle`/`shardLines` = Jackie's Rocky Ridge note. Both in-character; edit prose to taste.
- **⚠️ Companion persistence (v0.72) DISABLED** — `Config.persist.enabled = false` — because the
  respawn-on-load **crashes the game**. Fact-tracking still runs; only auto-respawn is off. See the
  START-HERE bug list at the top; this is the #1 fix for next session.
- Version 0.74 → **0.75**. All three files compile clean (`luajit -bl`), still under the 200-local cap.

## 🆕 v0.74 — tutorial popup NOT working yet → in-game PROBE to find the right CET call (2026-07-01)
The v0.71 native-popup push still falls back to the **blue band** on the live build. Root-caused as far
as the dev machine allows: the game's own `popupManager.script` **confirms the recipe** — the
always-present popup manager registers a DELAYED listener on the `UIGameData` blackboard's `Popup_Data`
and its `OnUpdateData` → `ShowTutorial()` builds the lower-left `TutorialPopupData`. Names all verified:
blackboard = `UIGameData` (same one our WORKING subtitles use), fields `Popup_Data`/`Popup_Settings`, both
`import struct` (so `.new()` is correct) with fields `title`/`message`/`isModal` + `position`/`closeAtInput`/
`pauseGame`/`fullscreen`/`hideInMenu`. So the failure is in **how CET marshals the struct into the
variant** (our subtitle code already needs an explicit `ToVariant(x, "type")` for its array — the popup
likely needs the same, or the `SignalVariant` call is the thing that throws).
- **New in-game probe:** CET window → "Tutorial popup probe (TEMP)" → **V1..V5** buttons. Each sets the
  blackboard a different way and logs every step's OK/ERR to the console:
  - V1 untyped `ToVariant` · V2 **typed** `ToVariant(x,"gamePopupData/Settings")` · V3 typed + `SignalVariant`
    · V4 typed + raise `Popup_IsShown` · V5 build structs with `NewObject` instead of `.new()`.
- [ ] **TEST:** click V1→V5, tell me **which one shows a real lower-left popup** (not the blue band), and
      paste the `[PopupProbe V#]` console lines. Then I bake the winner into `retrieval.lua` `tutorialPopup()`
      and delete the probe.
- Version 0.73 → **0.74**. (Offer still open: I can pull the Dark Future mod source as a reference if the
  probe doesn't crack it — but popupManager.script is the authoritative source and I have it.)

## 🆕 v0.71 — Vik tip = native lower-left TUTORIAL POPUP (Retrieval P2) (2026-07-01, ⚠️ NOT working yet — see v0.74)
v0.69 confirmed the gate works in-game (entering Vik's clinic flips the stage to TIP and the blue band
appeared). v0.71 replaces that plain blue on-screen band with the real **native lower-left tutorial
popup** (the "Dark Future" method from Retrieval P2).
- **Where:** implemented entirely inside `retrieval.lua` (its own Lua chunk → own local budget, so this
  does NOT touch init.lua's 200-local cap). New self-contained `tutorialPopup(title,text)` primitive +
  `lowerLeftPosition()` helper; `showTip()` now tries the native popup FIRST, then the (still-unbound)
  injected `deps.showTip`, then the old on-screen band as a last-resort fallback. Nothing in init.lua
  changed — no new bind needed.
- **API (confirmed against the game's reflection data, not guessed):** the `UIGameData` blackboard (the
  same one our subtitles use) → set `Popup_Settings` (`gamePopupSettings`: `position`,`closeAtInput`,
  `pauseGame`,`hideInMenu`,`fullscreen`) + `Popup_Data` (`gamePopupData`: `title`,`message`,`isModal`)
  → `bb:SignalVariant(Popup_Data)`. Position = `gamePopupPosition.LowerLeft` (=3). Every field assign is
  pcall-guarded and the whole push is pcall-wrapped, so a build mismatch degrades to the on-screen band
  instead of erroring.
- **Behaviour:** the popup is `closeAtInput=true` / `pauseGame=false` — it sits lower-left like a real
  tutorial card and the player dismisses it (no fixed timer). Both the Vik tip AND the Rocky Ridge shard
  now render through it (both go via `showTip`). `tipDuration`/`shardDuration` only matter to the fallback.
- Version 0.7 → **0.71**. `retrieval.lua` compiles clean (`luajit -bl`).
- [ ] **TEST:** enter Vik's clinic (or CET → "Force tip") → a native popup appears LOWER-LEFT with the
      "A message from Vik" title + tip text (not the blue band), dismissable with a keypress. Drive to
      Rocky Ridge (or "Force shard") → the shard renders the same way. If it still shows as the blue band,
      the console logged `tutorial popup push failed` — copy that line back.

## 🆕 v0.7 — CET live spacing tunables + subtitle non-issue cleanup (2026-07-01, awaiting in-game test)
- **CET window: live companion-spacing sliders.** New "Companion spacing (live tuning)" section in the
  Jackie Lives overlay (inside `onDraw`, so NO new top-level locals — respects the 200-local cap):
  - **Follow gap (m behind V)** → `Config.follow.distance` (1–8 m)
  - **Catch-up trigger (m from V)** → `Config.catchUp.distance` (8–60 m)
  - **Catch-up drop (m beside V)** → `Config.catchUp.placeDistance` (1.5–8 m)
  The follow/catch-up ticks read these every frame, so dragging a slider changes his behaviour instantly,
  no redeploy. LIVE-ONLY (reset to config.lua defaults on reload) — once a value feels right, tell Claude
  and we bake it into config.lua.
- **Subtitle "bug" = NON-ISSUE.** Subtitles were just turned OFF in the game Settings on the rig. Removed
  the v0.67 debug scaffolding (`Config.debugSubtitles` + the success-path mirror in `showSubtitle`) and all
  the subtitle-bug notes. Antonia is adding "make sure in-game subtitles are enabled" to the Nexus page
  (cyberpunk2077/mods/31042).
- Version bumped 0.67 → **0.7**.

## 🆕 v0.69 — reunion status line + dead-code cleanup (200-local headroom) (2026-07-01, awaiting in-game test)
- **Status line** at the top of the CET window: `Reunion quest: <stage>` (blue). Player-facing stage names
  in `retrieval.stageName()`: **Mod not yet available** / **V heard the rumor — find Jackie in the Badlands**
  / **Jackie's note was read at Rocky Ridge — he's on his way** / **Jackie is back**.
- **Dropped dead code (Antonia approved) → 196→183 locals (big headroom now):**
  - VO-test trio `playNamedEvent`/`playVO`/`playRandomJackieEvent` + the "play random voice" debug hotkey
    (`jl_votest`) — superseded by the dialogue/subtitle system.
  - The entire native-phone PROBE subsystem (`PROBE_CANDIDATE_CLASSES`, `methodName`, `dumpPhoneReflection`,
    `probeFire`, `setupNativePhoneProbe`) + its `Config.probeNativePhone` call — the phone system is solved.
- **KEPT (was a false positive in my first list):** the native choice-box cluster (`showJackieChoiceBox` /
  `hideJackieChoiceBox` / `buildJackieHub` / `choiceBox`) is **live** — it draws the "[F] Talk" prompt when
  you look at Jackie (toggled by `Config.talk.useChoiceBox`). Not dead; left intact.
- [ ] **Tiny leftover for the future cleanup pass:** `getTalkTarget` is now unused (was only called by the
      deleted VO trio). Harmless; remove on the next sweep. `Config.probeNativePhone` flag also now unused.
- [ ] **TEST:** mod still loads + behaves; the status line shows at the top of the window.

## 🛑 v0.68 — CRITICAL load-fix (200-local cap) + Retrieval quest Phase 1 (2026-07-01, awaiting in-game test)

### 🛑 CRITICAL — init.lua hasn't loaded since v0.66 (200-local-per-function cap)
**v0.66 silently crossed Lua's HARD limit of 200 locals per function**, so the `init.lua` main chunk
fails to compile: `main function has more than 200 local variables`. Confirmed on Mac with `luajit
loadfile`: HEAD~2 (200) LOADS, **v0.66 (201) FAILS, v0.67 (202) FAILS** → the last two tags don't load
in CET at all (both "awaiting test", so never caught in-game).
- **Fix:** 6 ancient leaf helpers changed `local function` → plain `function` (globals; one-token each,
  no call-site/behaviour change): `getAMMCharacters`, `discoverJackieFromSpawned`, `diagnostics`,
  `dismissAllJackies`, `capturePosition`, `probeChoiceBoxAPI`. Now **196 locals (4 headroom)**. Header
  note added in init.lua. **New top-level code must use globals or a module, never a main-chunk `local`.**
- ⚠️ `staging/` copy is the broken v0.67 — mirror this fix + `retrieval.lua` when the mute release unparks.
- [ ] **TEST:** reload CET → no red `init.lua` error (it loads at all). That alone confirms the fix.

### 🆕 Retrieval questline ("Where's Jackie?") — Phase 1: gate + state machine (DEPLOYED, awaiting test)
New module `mod/JackieLives/retrieval.lua` + ~8 surgical init.lua hooks. Per-save game fact
`jackielives_stage` GATES the whole mod: LOCKED → TIP → SHARD → (call/arrival/reunion) → REUNITED.
- Gate wired into `scheduleTick` (Jackie absent), `summonJackie`/`startCall` ("Number disconnected"),
  `onPlayerCalledJackie` (rings out). Coords: Vik `{-1546.551,1229.270,11.520}` r4; Rocky Ridge garage
  `{2575.852,0.291,80.871}` yaw 129.8 r4. Shard = on-screen text (no WolvenKit). Pin reuses dinner mappin.
- Precondition (≈ q101 "Playing for Time" Succeeded) is configurable + `debugQuestState()`; **ships OFF**
  so it's testable without the prologue — flip to `"quest"` after confirming the journal path in-game.
- Debug UI: CET window → "Retrieval quest (Where's Jackie?)" → Force tip / Force shard / Quest probe / Reset.
- [ ] **TEST Phase 1:** Force shard → ~1 s → stage REUNITED (schedule/calls come alive). Real flow: reach
      Vik (tip + Badlands pin) → drive to Rocky Ridge (shard) → ~1 s → unlock.
- [ ] **Enable the real gate on "Playing for Time" (q101) — Antonia confirmed (2026-07-01).** After that
      job completes, V can return to Vik and the tip/tutorial-overlay should become available. Steps: stand
      at Vik post-q101 → click **Quest probe** → read the `[Retrieval]` console state for "Playing for Time"
      → put that journal path into `retrieval` `gate.questPaths` and set `gate.mode = "quest"`. Until then it
      ships OFF (fires on Vik proximity alone).

### ▶ NEXT — Phases 2-4 (researched, ready)
- **P2 Vik tip = native LEFT tutorial popup** (Dark Future method): `UIGameData` `Popup_Settings`+`Popup_Data`
  (`gamePopupData/Settings`, pos `LowerLeft`) → `SignalVariant(Popup_Data)`. Pure CET Lua, confirmed.
  ✅ **DONE in v0.71** — `retrieval.lua` `tutorialPopup()`; both tip + shard use it. Awaiting in-game test.
- **P3 one-time incoming call FROM Jackie** (mute monologue): no native path → wrapper sets `Branch.busy`,
  `JL.call.connectAt=clock+0.2`, `Branch.start(start, Config.retrievalCallTree)`; terminal node arms a foot arrival.
- **P4 safe walk-in arrival** (`JL.varrival.at`, `useBike=false`) **+ reunion `Branch` tree**; choice labels
  are plain strings so a **"Lie:"** prefix works (V lies re: the Relic). Reunion end → `setStage(REUNITED)`.

## 🆕 v0.67 — keep-close follow + Bug-1 narrowed (DEPLOY + test, 2026-06-30)
Follow-ups after the first v0.66 test pass.
- **Keep-close follow (NEW).** Jackie trailed FAR behind V (AMM's long companion leash). New
  `followKeepCloseTick` + `Config.follow` re-asserts our tight `AIFollowTargetCommand` every `interval`
  (1.5 s) at `distance` (2.5 m) while he's a settled companion — overriding AMM's leash. Tunable;
  set `enabled=false` or raise `interval` if it looks jittery. Tiers under catch-up (which owns >25 m).
  - [ ] TEST: he now holds ~2.5 m behind V on foot; no stutter/surge. Tune `Config.follow.distance` to taste.
- **Bug 1 narrowed.** Reported on a NORMAL call (no visible struggle) → rules out the stuck-fallbacks.
  Arrival uses `spawnDynEntity` at the FAR navmesh point (50/60 m), never at V — so on this build the
  distance spawn isn't being honoured, OR `navmeshArrivalPoint` returned nil → `arrivalPoint()` fallback
  (18 m fwd). NEEDS: console lines from that call — `Call: arrival navmesh point...` / `FootApproach:
  spawned ~Nm` / `VehArrival:` — to see the actual spawn distance + whether the navmesh point was valid.
- **NEXT (Antonia's call):** persist the companion flag (List_of_companion_issues.md Session 1) — survive
  save/load + load-screen fast-travel by re-spawning + re-promoting Jackie at V from a saved intent flag.

## 🆕 v0.66 — companion catch-up teleport (fast-travel "never get lost") (DEPLOY + test, 2026-06-30)
Returning bugs reported on the new gaming rig (game 2.31, CET 1.37.1, AMM 2.12.5, Codeware 1.20.3).
Diagnosed from code; shipped the fast-travel fix.
- **#3 FAST-TRAVEL / left-behind (FIXED in code, awaiting test).** Root cause: there was **never** a
  fast-travel handler (it's List_of_companion_issues.md Session 1 backlog — planned, not built). On top of
  that, the arrival design intentionally **suppresses** the catch-up teleport post-arrival ("teleport powers
  only return when he's already next to V", see v0.50 notes), so a settled companion had **no** way to catch
  up. New `catchUpTick` (init.lua) + `Config.catchUp`: while he's a settled, undismissed companion and NOT
  mid-arrival/dinner/walk-off, if he's >`distance` (25 m) from V for >`sustainSeconds` (2 s) he's `aiTeleport`-ed
  to a navmesh point `placeDistance` (3 m) to V's **side** — our own teleport, our chosen offset, so he never
  lands on V. Limit: a load-screen FT that culls his entity (handle nil) still loses him → Session-1 persist+respawn.
- **#1 "spawns inside V" (DIAGNOSED, partial).** The catch-up always lands him beside V now, but the original
  yank-onto-V is from the **arrival FALLBACKS** — `rescue-spawn at V` (ammSpawn at V's pos) and the `maxSeconds`
  force-handoff (AMM catch-up to V's face) — which fire when he gets **stuck approaching**. Verdict: ~half AMM
  trait (companions stand very close + catch-up lands on target), ~half ours (we lean on at-V fallbacks). Needs
  in-game obs: normal arrival vs stuck-only? Then offset those fallbacks beside V too.
- **#2 subtitles — NON-ISSUE (resolved 2026-07-01).** Subtitles were simply turned OFF in the game's
  Settings on the rig; nothing wrong with our push. No code change. (End-user note "make sure subtitles are
  enabled" is going on the Nexus page.)

## 📦 Session 2026-06-30 — MUTE Nexus release packaging (staging tree added, no code changed)
First-time release prep on a Mac clone (code/docs only; Windows machine does deploy + in-game test).
- **Decision:** ship a **mute version (no voice audio)** — CDPR voice `.ogg`s can't be redistributed.
- **Audio crash-check (mute, Audioware installed but no clips registered): PASS, no code change.**
  Every audio entry point is `pcall`-guarded and degrades to subtitles + fallback timing:
  `playVoice`/`voiceDuration` (init.lua ~1222/1229), `playEventOn` (~437), callers
  `speakJackieLine`/`dialogueTick`. Safe whether Audioware is present, absent, or `GetAudioSystemExt()`
  is nil; nothing touches audio at load.
- **Added `staging/bin/x64/plugins/cyber_engine_tweaks/mods/JackieLives/`** = zip-ready CET mod folder
  (`init.lua`, `config.lua`, + a clean **end-user README.md**). Excludes the dev probe mods and all audio.
  On Windows: `git pull` → zip the `staging/bin` folder (root must be `bin\`) → upload as the Main file.
- **Nexus requirements to list (mute):** CET 1.18.1+ · AMM · Codeware · Native Settings UI (mod 3518,
  folder must be `nativeSettings`). NOT needed: Audioware, redscript, TweakXL, ArchiveXL.
- [ ] **TODO:** keep `staging/` in sync with `mod/JackieLives/` on future code changes (or write a
      `package.ps1` to build the zip from source instead of a checked-in staging copy).
- [ ] **TODO:** trim the shipped README's old `deploy.ps1` reference is already removed in staging — but
      the dev `mod/JackieLives/README.md` still documents deploy (intentional; dev-only).

## 🆕 v0.65 — bike-model test: try DIFFERENT records (the v0.63 record was wrong) (DEPLOYED, awaiting test, 2026-06-23)
The v0.63 tester's 3 methods all used ONE record (`v_sportbike2_arch_jackie_player`) and ALL spawned the
WRONG bike → that record doesn't give his Arch via DES on this build. Researched the actual records
(CET vehicle list + redmodding wiki + game files): Jackie's Arch model lives under the entity
`v_sportbike2_arch_nemesis`; the garage wrappers are `*_player` records. Rebuilt the "Bike model test"
buttons to spawn 3 DIFFERENT candidate records (in `BIKE_CANDIDATES`, trivially editable):
- **B1** `Vehicle.v_sportbike2_arch_jackie_tuned_player` — his TUNED Arch (Heroes reward; most likely).
- **B2** `Vehicle.v_sportbike2_arch_nemesis` — the Arch model entity itself.
- **B3** `Vehicle.v_sportbike2_arch_player` — standard Arch Nazaré (control).
Each spawns ~6 m in front + logs a `READ-BACK` (record/appearance/class). "Dump appearances" now dumps
all three candidates. Note: "La Chingona Dorada" is Jackie's GUN, not the bike — the bike is just his Arch.
- [ ] **TEST:** click B1/B2/B3; tell me which is his real (gold) Arch + the READ-BACK appearance string.
      Then I lock that record+appearance into the live `spawnDynEntity` bike spawn. If none look right,
      the read-back record ids + appearance dump will point to the correct one.

## 🗒️ Session 2026-06-23b — RELEASE PLANNING + init.lua module split (DISCUSSION ONLY, no code changed)
No deploy this session. Two threads opened for later; nothing implemented yet.

### Thread 1 — Nexus / mod-manager publishing (researched, NOT started)
- **"Download with Mod Manager" is basically free** once the upload zip mirrors the game root. Vortex/MO2
  already understand Cyberpunk's layout — no custom manifest needed. Zip internal structure must be:
  - `bin/x64/plugins/cyber_engine_tweaks/mods/JackieLives/`  (init.lua, config.lua, README)
  - `r6/audioware/JackieLives/`  (manifest + audio — but see copyright blocker)
- **Dependencies = Requirements tab, NOT bundled:** RED4ext, CET, redscript, TweakXL, ArchiveXL, Codeware,
  Audioware, AMM (if hard runtime dep). Pin game patch in the description (version drift = #1 breakage).
- [ ] Write `package.ps1` that builds the Nexus-ready zip (mirror-root structure) — deferred.
- [ ] Draft Nexus page text + requirements list — deferred.
- **⚠️ COPYRIGHT BLOCKER (the real issue):** the Audioware bank ships Jackie's REAL CDPR voice lines
  (940 MB of `.wav` in `audioware/JackieLives/`, already gitignored per `ASSETS_NOTICE.md`). **Cannot be
  redistributed on Nexus — page would be taken down.** Three release options discussed:
  - **A. Ship script, not audio** (repo is already built for this: `tools/scrape_jackie.py` +
    `tools/convert_audio.py` rebuild the bank from the user's OWN game). Clean, standard Nexus pattern. ← recommended
  - **B. Ship silent** (text/subtitles only). Cleanest, least immersive.
  - **C. AI/TTS Jackie voice.** Legally grey (real VA Jason Hightower's voice) — many sites disallow.
  - **Antonia is "working on a better way"** for voice distribution — PARKED pending her approach. Don't
    package a release until the voice route is decided.

### Thread 2 — split `init.lua` (4097 lines) into modules — AGREED in principle, leaf-first, NOT started
Verdict: yes, modular is the pro/collaborator-friendly approach. Mechanism is LOW RISK — `require()`
already works here (`init.lua:51` = `local Config = require("config")`; CET puts the mod folder on the Lua
path). The one real obstacle: Lua `local`s don't cross files, and init.lua leans on forward-declared local
upvalues. **Seam = the existing `JL` shared table** — promote cross-referenced locals onto `JL`, each module
attaches there. Do it INCREMENTALLY, one commit per module (fits the commit-every-working-version rule),
leaf modules first, central dialogue hub LAST.

Proposed module map (line ranges approx, from this session's read):
| Module → `modules/*.lua` | init.lua lines | priority |
|---|---|---|
| diag.lua (diagnostics + native-phone probes) | 208–257, 3483–3565 | 🟢 FIRST (proves pattern) |
| voice.lua (Audioware playback) | 422–479, 1220–1296 | 🟢 |
| ui.lua (ImGui window + seat tuner, onDraw) | 1427–1606, 3935–4236 | 🟢 (big readability win) |
| holocall.lua (holocall + native phone) | 1714–2009 | 🟡 |
| arrival.lua (navmesh, walk-in, bike state machine) | 2011–2975 | 🟡 (large) |
| dinner.lua (dinner outing) | 1336–1426, 3097–3306 | 🟡 |
| idle.lua (schedule, wander, poses) | 482–637, 2977–3479 | 🟡 |
| dialogue.lua (runner + branching + choice box) | 638–1335, 1607–1713 | 🔴 LAST (central hub) |
| core/utils (spawn, teleport, follow, time, subtitle) | scattered | extract as foundation |
init.lua then = thin orchestrator: define `JL` → `require` each module → event/hotkey wiring (3727–4259).

- [ ] **NEXT STEP (decide which first):** extract `modules/diag.lua` (lowest risk, proves the require
      pipeline) OR `modules/ui.lua` (bigger readability win, still leaf-ish). Antonia to pick. Then deploy,
      confirm in-game (diag prints / window opens), commit `refactor: extract <module>`, walk up the table.
- [ ] Decide a module convention before the first extraction (everything public hangs off `JL`, modules
      receive `JL`+`Config` and return/attach their public fns).

### Reference fact (mod size without audio/labels)
Code-only footprint (no audio, no line/label DBs): **~296 KB on disk, ~94 KB zipped.** init.lua=210 KB,
config.lua=65 KB, rest ~20 KB. The 940 MB is ENTIRELY the `.wav` voice bank; `index.json`+`JackieLives.yml`
labels add ~200 KB. A code-only release is effectively a sub-100 KB download.

---

## 🆕 v0.65 — companion-issue triage: config tweaks + stuck-arrival rescue (DEPLOY + test, 2026-06-23)
- **Phone unavailability → 4h/night, 02:00–06:00** (`Config.secret.startHour 0 → 2`; endHour stays 6).
  Phone pickup is gated only by this window (`jackieAsleep`, init.lua:611).
- **Default arrival method = bike** (`Config.call.arrivalMethod "foot" → "bike"`). The CET window reads
  this value live (toggle at init.lua:4115), so bike is now the window default too.
- **Bike stuck failsafe more lenient:** `Config.vehicle.stuckSustain 8 → 10` REAL seconds (a traffic
  light can hold 7s+). `stuckGrace` (8s) and the slowDownDistance suppression unchanged.
- **Arrival spawn delay kept at 2s** (`vehicleSpawnDelay = 2.0`; an earlier +6s was reverted).
- **Stuck-arrival RESCUE-SPAWN (init.lua `maxSeconds` deadline handler).** Root cause of "after being
  really really stuck he NEVER spawns": the 120s safety deadline called `promoteToCompanion`, which
  silently no-ops when there's no Jackie handle (DES spawn failed / body lost) — and the old
  AMM-spawn-near-V fallback was deleted in v0.50, so nothing re-spawned. Now: handle exists → force
  handoff as before; NO handle → despawn orphans, reset state, **rescue-spawn a fresh companion at V**
  (the main tick auto-promotes). Last-resort only (after full 120s), so no in-face pops in normal use.
- [ ] **TEST:** (a) calls 02:00–06:00 ring out, calls outside that connect. (b) Arrivals default to bike
      in the window. (c) Bike no longer bails to foot at a normal traffic light. (d) Force a stuck/failed
      arrival → console shows `rescue-spawn at V` and Jackie appears at V instead of never showing.
- [ ] **STILL TO DIAGNOSE:** when he "never spawns," is his handle nil (→ rescue branch) or is he
      alive-but-stuck-MOUNTED (handle resolves, but catch-up teleport can't move a mounted NPC)? If the
      latter, add a force-dismount-then-teleport to the `resolveJackieHandle()` branch. Report which
      console line fires.


## 🆕 v0.64 — smile tuning + dinner objective = neon-left flash (DEPLOYED, awaiting test, 2026-06-19)
- **Smile chance:** middle ground `0.025 -> 0.033`; new `Config.smile.dinnerChance = 0.04` used by
  `smileTick` whenever `JL.dinner.phase` is set (he smiles more on the dinner outing).
- **Dinner objective restored to the native neon-left flash.** The persistent top-center ImGui blue
  box (`drawDinnerObjective`) was the wrong UI — DELETED (function + onDraw call). `startDinnerWalk`
  now fires ONE `showOnscreenMsg(...)` flash via the `UI_Notifications.OnscreenMessage` blackboard
  (`SimpleScreenMessage`) — the same neon-left system we used before subtitles existed. Map pin still
  guides the rest of the way.
- **Message text updated:** `Config.date.objectiveText = "Grab some food with Jackie: Go to %s"`
  (+ `objectiveDuration = 6.0` s).
- [ ] **TEST:** start a dinner outing -> neon-blue "Grab some food with Jackie: Go to <place>" flashes
      on the left for ~6 s (NOT the top-center box). While walking/at dinner, smiles come a bit more
      often than normal.

## 🆕 v0.63 — bike-model test harness (find Jackie's REAL Arch) (DEPLOYED, awaiting test, 2026-06-19)
Problem: the bike arrival often spawns the WRONG bike model/livery. During the vehicle-testing phase
it reliably spawned the right Arch; now it doesn't. Live + test both spawn the same record
(`Vehicle.v_sportbike2_arch_jackie_player`) the same way (string recordID + `appearanceName="default"`),
so the cause is either appearance resolving to a random/fallback livery or the recordID string not
pinning the model — needs in-game evidence to tell which.
- **3 spawn approaches as buttons** under a new "Bike model test (spawn Arch in front)" collapsing header
  in the main CET window. Each spawns the bike ~6 m in front of you, then logs a **READ-BACK** line of
  what ACTUALLY spawned (record + appearance + class):
  - **M1** = record string + appearance `"default"` (exactly what the live arrival does now — the control).
  - **M2** = record string + explicit `Config.vehicle.bikeAppearance` (pins the livery; currently "default").
  - **M3** = recordID as `TweakDBID.new()` + record-default appearance (tests a string-coercion / default bug).
  - Plus "Dump appearances (console)" (best-effort TweakDB read) and "Despawn test bike".
- New `Config.vehicle.bikeAppearance` knob for M2 / the eventual live fix.
- [ ] **TEST:** open the header, click M1/M2/M3 in turn, and tell me (a) which spawns his correct gold Arch
      and (b) the console `READ-BACK` appearance string for each. Then I lock the winning method +
      appearance into the live `spawnDynEntity` bike spawn so arrivals always use his real bike.

## 🆕 v0.62 — CET window declutter + main-quest detection + companion safety dismount (DEPLOY + test, 2026-06-19)
- **Disabled the VEHICLE + LIPSYNC test windows.** Renamed their deployed `init.lua → init.lua.disabled`
  in the game's CET mods folder (windows gone on reload; nothing deleted). Source stays under `mod/`
  so `deploy_probe.ps1 -ModName JackieVehicleTest|JackieLipsync` redeploys them instantly to test again.
- **Decluttered the main "Jackie Lives" CET window** — permanently removed the UI for: push-subtitle test,
  NATIVE phone test (RING/CONNECT/END/Force-hang-up), "Play branching dialogue" button, proximity-bark +
  bump-grunt sliders, the "Arrival test modes" (BEHIND/foot-dist/arrive-dist) block, and the picker-styles
  (testV1/2/3) block. Underlying systems (subtitles, native call, barks, branching dialogue, picker) are
  untouched — only the debug buttons are gone. Kept the force-main-quest test checkbox + a live "Main quest
  detected" readout.
- **MAIN-QUEST DETECTION (real, replaces the stub).** `isMainQuestActive()` now reads the player's
  currently TRACKED journal quest (`JournalManager:GetTrackedEntry` → walk parents → `gameJournalQuestType`
  name-match on "Main"), cached ~0.5 s, fully pcall-guarded (defaults to "not main" so a reflection hiccup
  can't wrongly block him). Already gates summon/call/arrival; NEW: if Jackie's tagging along when a main
  quest goes active he **excuses himself and walks off** (`Config.mainQuestExit`, reuses the send-off
  walk-off; line currently = the send-off VO, TODO a dedicated clip).
- **COMPANION SAFETY DISMOUNT (bike).** `promoteToCompanion` now checks `isMounted()` (mounting facility)
  and re-issues ONE unmount if Jackie's somehow still in the bike seat at handoff — gated so a foot arrival
  or already-grounded Jackie never plays a phantom get-off.
- [ ] **VERIFY main-quest API in-game:** the journal reflection (`GetTrackedEntry`/`GetParentEntry`/`GetType`
      → "Main") is best-effort — confirm the "Main quest detected" readout flips YES during an actual main
      quest and stays "no" on side jobs / free-roam. If it never flips, we adjust the reflection path.
- [ ] **TEST:** (a) both test windows gone from CET, JackieLives window is tidy. (b) Tracking a main quest →
      "Main quest detected: YES", summon declines, and a tagging-along Jackie excuses himself + leaves.
      (c) Bike arrival where he used to stay seated → safety dismount fires (`still mounted -> safety dismount`).

## 🔬 Track A — native line-by-stringId + baked lipsync (probe, awaiting test, 2026-06-19)
Goal: make a SPAWNED Jackie speak a SPECIFIC line by VO string id WITH the game's own baked
lipsync, WITHOUT authoring a `.scene` file. If it works, the heavy WolvenKit scene-authoring
route (Track B) is unnecessary.
- **Built:** standalone CET probe `mod/JackieSceneProbe/` + `deploy_probe.ps1`. Dump-first
  pattern (same one that cracked the phone system): reflection-dump scene/voiceset/dialog/VO
  classes → `scene_methods.txt`; placeholder "play the line" attempts → `scene_attempts.txt`.
  Test line: **"Ka-ching, baby!"** stringId `1927336253241237504`, lipsync `f_1ABF461C612D2000`.
- [x] **TEST done (v2 full dump, 2026-06-23):** `scene_full.txt` — all 4380 globals + key classes.
- [x] **VERDICT: Track A (runtime play-by-stringId) is NOT supported by the API.** No script
  function plays a specific line by id. Only VO door is `PlayVoiceOver(context)` (game picks the
  line, auto-lips); `scnVoicesetComponent` has 1 script method; scene classes are native. Saved to
  memory `track-a-no-runtime-line-by-id`.
- [x] **DECIDED (2026-06-23): Track C** — play each line's baked facial anim on `face_rig` +
  our Audioware audio. (B scene-authoring shelved as too heavy; ship-hybrid = the fallback.)

### ▶ NEXT SESSION — Track C: baked facial anim + Audioware audio (real per-line lips)
**Idea:** our Audioware audio carries no facial data, but every line already has its baked
facial-anim hash (`lines.json` `lipsync` field, == wem hash, e.g. `f_1ABF461C612D2000`).
Jackie's `face_rig` is a live `entAnimatedComponent`. So: play the line's facial anim on the rig
while the Audioware clip plays → real lips on our exact lines, no scene authoring. Test target:
**"Ka-ching, baby!"** (`jl_1927336253241237504`, anim `f_1ABF461C612D2000`).
Open tasks (in order):
- [ ] **Locate the facial-anim resource** for a known hash in WolvenKit: where do per-line lipsync
  anims live in the archive (likely `base\characters\...` facial `.anims`, or referenced from the
  scene)? Confirm `f_1ABF461C612D2000` is a standalone-playable `.anim` vs embedded in a scene/setup.
- [ ] **Extend the export wscript** (the audio one over `vo_wem`) to also export the matching facial
  anim per line by its hash — or confirm we can play the in-archive anim directly without extracting.
- [ ] **Find the play-anim API** on `entAnimatedComponent` / `AnimationControllerComponent`:
  extend `JackieSceneProbe` to dump those two classes' methods and try playing ONE known facial
  anim by name on `face_rig`. (Reflection dump pattern already in the probe.)
- [ ] **Sync test:** fire the facial anim + the Audioware clip together on summoned Jackie; eyeball
  lip sync on "Ka-ching, baby!". Tune offset if needed.
- [ ] If standalone facial anims aren't playable on the rig → fall back to ship-hybrid for V1
  (PlayVoiceOver contexts + cat-7 talking flap; both already work).
- **Refs:** verdict in memory `track-a-no-runtime-line-by-id`; flap+voiceset recipe in
  `jackie-facial-rig-runtime`; raw probe output lives in the deployed mod folder
  (`...\mods\JackieSceneProbe\scene_full.txt`), regenerable via the probe's "1b) FULL dump".
- **Distribution note:** per memory `nexus-publishing-constraints`, ship build scripts (export
  wscript), NOT the extracted CDPR audio/anims.
- Audio-only V1 export (wscript over `lines.json` `vo_wem`) is the separate, already-scoped path.

## 🆕 v0.55 — arrival/immersion tuning + asleep-no-pickup + ambient grunts + dinner gate ON (DEPLOYED, awaiting test, 2026-06-19)
Batch of small polish + two new behaviours.
- **Foot arrival downshift 25→14 m** (`Config.vehicle.sprintToWalk`): he now sprints closer and only
  walks the last 14 m (was 25).
- **Spawn wait 2× again:** `Config.call.vehicleSpawnDelay` 1.0→**2.0 s** (the delay actually used before
  he spawns post-call); `spawnDelay` restored 2.5→5.0 for consistency (legacy, unused in the live path).
- **Smile a bit rarer:** `Config.smile.chance` 0.04→**0.025**/roll.
- **Dinner gate ENGAGED:** `Config.date.enforceUnlock` false→**true** — the "Wanna get something to eat?"
  invite now only unlocks after **1 in-game hour** out together (`unlockAfterGameHours`, measured from
  `companionSinceGame`). `dateUnlocked()` already implemented the gate; this just turns it on.
- **Asleep = no pickup (NEW):** new `jackieAsleep()` (true during the `Config.secret` sleep window,
  00:00–06:00). Calling him then doesn't connect:
  - Our holocall button/hotkey (`startCall`): rings `asleepRingSeconds` (7 s) then auto hangs up
    (`callTick` `noAnswerAt` branch fires `EndCall`), shows "No answer." No convo, no spawn.
  - Native phone (`onPlayerCalledJackie`): we simply DON'T hijack → the game's own ring plays out and
    auto-hangs-up (Jackie never "picks up"). Matches "hook won't trigger, just rings until it hangs up".
- **Ambient "feel alive" grunts (NEW):** `ambientGruntTick` — while Jackie's present (companion OR idle)
  and not mid-talk/call, every `everyMinutes` (10) REAL min there's a `chance` (10%) he plays ONE
  NON-PAINED vocal effort (laugh/huff/curious/greet). Pool in `Config.ambientGrunt.events` deliberately
  excludes pain/choking/scream/death + attack barks. Same WWise path + talk-locks as the smile.
- [ ] **TEST:** (a) call Jackie between 00:00–06:00 → rings, no pickup, hangs up with "No answer".
      (b) Be a companion <1 in-game h → no dinner invite; after 1 h it appears. (c) Hang around idle/
      companion Jackie a while → occasional casual grunt (console `Ambient: '...'`), never a pained one.
      (d) Foot arrival → he walks only the last ~14 m. (e) Post-call spawn wait feels ~2 s longer.
- **Open thoughts (decide next session):**
  - [ ] Ambient grunt pool is 7 calm events (greet/curious/huff/additional/laughs×3). Add effort/attack
        variants for variety if it feels repetitive? (Excluded for now — they read as hurt/fighting when idle.)
  - [ ] Dinner "out together for 1 h" = companion clock since join, which **resets on dismiss + re-summon**.
        Confirm that's the intended reading (vs. cumulative lifetime); tune `Config.date.unlockAfterGameHours` if not.
  - [ ] `jackieAsleep()` keys off the 00:00–06:00 sleep window only; "home but awake" blocks still let him
        pick up. Probably fine — extend to any "unavailable" block only if Antonia wants stricter availability.

## 🆕 v0.52–v0.54 — arrival tuning: side spawn, bike park+walk, mount timing, fell-off, no face-teleport (DEPLOYED, awaiting test, 2026-06-19)
Iterative polish on the v0.50 two-mode (foot/bike) arrival. See `docs/logbook.txt` "ARRIVAL OVERHAUL" for the full narrative.
- **Side spawn (v0.52):** `navmeshArrivalPoint` spawns him on a SIDE of V (left/right, 90°±20°, random),
  not behind. `Config.call.spawnSides` (default on). v0.53: falls back to the **other side, then BEHIND**
  if a side has no walkable point (a 90° point often lands in a building → unreachable).
- **Bike park + walk (v0.52):** spawn 80→**60 m** (stays in the streamed zone), slow at **30 m**, PARK on
  the road + dismount at **20 m**, then WALK the rest (was sprint). Stuck-failsafe disabled while
  deliberately slowing; bike stuck timers doubled.
- **Bike mount fix (v0.54):** `mountSeconds = 4` gives Jackie real time to climb on before the bike
  drives; if he's then >`fellOffDist` (6 m) from the moving bike the mount failed → ditch the bike, he
  walks in on foot from there. The progress ping now reports JACKIE's distance to V, not the bike's.
- **Companion handoff 18→5 m (v0.50)** so AMM's catch-up teleport can't yank him into V; **stuck-respawn
  ladder** ends at **20 m not 5 m (v0.54)** — a 5 m respawn read as a "teleport to V's face".
- **Stuck timers 2× (v0.52):** `respawnStuckSeconds` 5→10 (foot was too twitchy).
- [ ] **TEST:** foot — no face-teleports, spawns to a side or `BEHIND` and walks in. bike — `mount sent;
      4s to climb on` → if mounted, `riding in... X to V (bike Y)` X≈Y; if not, `Jackie NOT on the bike ->
      on foot`. If that fires EVERY bike run, the AIMountCommand is broken on this patch (needs rework).

## 🆕 v0.53 — catch-his-eye smile (DEPLOYED, awaiting test, 2026-06-19)
Tier-3 immersion: when V holds their gaze **straight on Jackie** (look-at, within range), a **low
chance per roll** that he flashes a **brief smile**, then his face relaxes.
- New `smileTick` (`init.lua`, beside `flapTick`) — reuses the proven `AnimFeature_FacialReaction`
  mechanism. Smile = native **category 3 / idle 6** (5=Joy, 2=Neutral; from `jackie-facial-rig-runtime`).
  Held by re-asserting the facial every `reapply` s, then `stim:ResetFacial(0)` to relax.
- **Gated OFF while he's talking** (`flap.until_ > 0`, `dlg.active`, `Branch.open/busy`) so a smile
  never stomps the mouth flap mid-line. Pure facial — no audio, no dialogue interrupt.
- Tunable in `Config.smile`: `chance` 0.04/roll, `rollEvery` 1.5 s, `duration` 3.0 s, `range` 8 m,
  `cooldown` 25 s (keeps it special), `reapply` 0.6 s.
- [ ] **TEST:** stand near idle/summoned Jackie and stare at him for a while. Occasionally (rare) he
      should smile for ~3 s then relax. Console logs `Smile: caught V's eye`. Confirm he never smiles
      mid-bark/dialogue. If the smile face looks wrong, sweep category/idle in `JackieLipsync` and
      update `Config.smile.category/idle`.

## 🆕 v0.51 — fix STUCK foot arrival: valid-spawn height guard + respawn-closer ladder (DEPLOYED, awaiting test, 2026-06-19)
**Symptom (Antonia's log):** a foot/sprint arrival spawned ~50 m out and STUTTERED in place —
`sprinting in... 50.7 m / 51.1 / 48.7 / 48.7 / 48.7 ...`, never closing. Cause: the spawn point was on
a navmesh island the path AI couldn't route from (wrong building level / blocked), so the MoveTo never
made progress. (NOT collision — the foot Jackie is a fresh DES entity with collision on.)
- **Height guard on the spawn point** (`navmeshArrivalPoint`): a snapped navmesh point is now rejected
  unless `|point.z - V.z| <= Config.vehicle.maxSpawnZDelta` (4 m). Keeps him on V's own floor — a
  same-level point is far likelier to have a walkable path. (The navmesh-below search could otherwise
  return a roof/balcony/metro/parking-deck point.)
- **STUCK -> RESPAWN-CLOSER ladder** (the catch-all, Antonia's idea): while sprinting/walking we track
  his CLOSEST distance to V; if it doesn't improve for `respawnStuckSeconds` (5 s) he's despawned and
  respawned at the next-closer `respawnRungs` (**35 -> 20 -> 5 m**). At 5 m he's on V's own navmesh, so
  it converges; if no rung is closer than where he's stuck, he just hands off to companion in place.
- Refactor: the foot spawn is now one helper `beginFootApproach(dist, reason)` reused by BOTH the
  initial arrival and every respawn rung (despawns any current Jackie+bike first → no duplicates).
- [ ] **TEST:** trigger FOOT arrival somewhere he used to get stuck. Console should show either a clean
      `BEHIND dist=50 dZ=+0.x` spawn that closes in, OR `STUCK at X m -> respawn closer at 35/20/5 m`
      until he reaches you. Confirm no duplicate Jackies and he ends as companion at ~5 m + grunt.

## 🆕 Esc-menu settings: Husbando toggle + Disable-vehicle-arrivals + PERSISTENCE (added, awaiting test)
- **Husbando mode** switch (Relationship): OFF = Hermano (canon, with Misty); ON = Husbando (closer to
  V, broke up with Misty). Sets `JL.husbando`. Nothing reads it yet — it's the hook for the work below.
- **Disable vehicle arrivals** switch (Arrivals): ON forces FOOT arrival regardless of
  `Config.call.arrivalMethod`. Wired: `runCallAction` gates `bike` with `and not JL.disableVehicleArrivals`
  (the single decision point at the `arrivalMethod == "bike"` line). Default OFF (bike allowed) so it
  doesn't surprise the concurrent arrival-overhaul work; players opt in when the bike glitches.
- [x] **Persisted across saves** (`jlSaveSettings`/`jlLoadSettings`). Self-contained `key=true/false`
      store in `jl_settings.txt` in the mod folder (NO json dependency — relative `io.open`, same as the
      phone probes). Loaded in `onInit`; each switch callback saves. `JL_SETTINGS_KEYS` = the persisted
      flag list; add future toggles there.
- [ ] **Hermano/Husbando = V-gender modes (added 2026-06-19):** **Hermano mode = male V**, **Husbando
      mode = female V** — these are V-gender-specific dialogue tracks. The voice bank now carries the
      `v_gender` tag on every line (`tools/tag_lines.py`; 108 male-V + 1174 female-V), so gendered
      branches can pull the correct variant — filter `lines.json` / the tagger by `v_gender`. See
      `docs/VOICE_LINES.md` § Line metadata.
- [ ] **Husbando-mode dialogue:** branch/alternate lines for talk, holocall, arrivals, dismiss when
      `JL.husbando` is true (terms of endearment, couple banter, no Misty references).
- [ ] **Husbando-mode venue schedule:** alternate `Config.daySchedules` / locations for husbando mode
      (e.g. shared apartment, different hangouts; no Misty's-shop stops).

### Esc-menu settings — backlog (next session can pick any; all back onto existing systems)
Pattern for each: add an `addSwitch`/`addRangeFloat`/`addSelectorString` in `nsTick`, store the value on
`JL.*`, add the key to `JL_SETTINGS_KEYS` (booleans persist automatically), and read the flag where the
system already decides. Sliders/selectors persist too but need their value serialized as text (extend
`jlSaveSettings`/`jlLoadSettings` beyond booleans — currently boolean-only).
- [ ] **Schedule on/off** (`Config.enableSchedule`) + **proximity radius** slider (`Config.proximityRadius`).
- [ ] **Arrival method dropdown** (foot / bike) — surfaces `Config.call.arrivalMethod`; supersedes the
      boolean "Disable vehicle arrivals" if added (keep them consistent).
- [ ] **Companion auto-leave** on/off + duration slider (`Config.companion.autoLeaveOnExpiry` + hours).
- [ ] **Proximity barks** on/off (`JL.bark.enabled`).
- [ ] **Dinner outings** on/off; **Secret nap cameo** on/off (`Config.secret`).
- [ ] **Buttons:** "Dismiss all Jackies" (lighter than Go Home); "Reset settings to default".
- [ ] **Debug subcategory** (hide normally): toggle `Config.probeNativePhone`; "Diagnostics" button.
- [ ] **Persistence: support non-boolean values** so the sliders/dropdowns above survive saves
      (`jlSaveSettings`/`jlLoadSettings` currently serialize booleans only).

## 🆕 v0.49–v0.50 — ARRIVAL OVERHAUL: bike revived + DES-unified to TWO modes (DEPLOYED, awaiting test, 2026-06-19)

### Decisions (Antonia) — why the arrival section was rebuilt
The arrival code had grown to 3 overlapping spawn machines + an invisibility hack + 2 spawn backends.
Root-cause research (git diff back to v0.36, the last version where the bike worked):

1. **Why bike "broke": the v0.38 foot-fallback.** The bike spawn/mount/drive code + `Config.vehicle`
   are BYTE-IDENTICAL to working v0.36. The only material addition since was `vehicleArrivalFootFallback`
   (v0.38): at **40 s** it despawned the bike + Jackie and respawned him on foot. An 80 m city ride
   routinely exceeds 40 s, so it was guillotining good rides ("no bike appears" = bike got nuked).
   → **v0.49: `Config.vehicle.footFallback` now defaults OFF.** Bike rides uninterrupted like v0.36;
   only the 120 s `maxSeconds` deadline is a backstop. The fallback code stays, opt-in.

2. **AMM-spawn vs DES — picked DES (Antonia's call, confirmed correct).** AMM spawns Jackie 1 m in
   front of V and instant-promotes to companion → that's exactly why the old "safe" path needed the
   HIDE-during-spawn + teleport-to-distance hack AND a `walkIn` flag to suppress the double-promote.
   DES spawns him EXACTLY at distance (no pop, no hide, no teleport, no race); `promoteToCompanion`
   still calls AMM's `SetNPCAsCompanion`, so we keep full follower/combat behaviour.

3. **Collapse to TWO modes (v0.50).** Deleted the AMM "safe walk-in" (`arrivalTick` + `arrivalMoveType`)
   and the entire invisibility subsystem from arrivals. Deleted the slow all-the-way "walk" approach.
   `Config.call.arrivalMethod` is now just **"foot" | "bike"**, both driven by `vehicleArrivalTick`:
   - **foot** — DES-spawn at `Config.vehicle.spawnDistance` (**50 m**) → SPRINT → swap to WALK at
     `sprintToWalk` (25 m) → companion → stop.
   - **bike** — Arch + Jackie at `bikeSpawnDistance` (**80 m**) → mount → ride → ease to `slowSpeed`
     at `slowDownDistance` (40 m) → park/dismount at `dismountDistance` (30 m) → same foot finish.

4. **Companion handoff moved 18 m → 5 m.** At 18 m, AMM's catch-up TELEPORT could fire on promote and
   YANK him into V — the "runs into V" bug. `companionDistance = 5.0` promotes him only once he's
   basically arrived, so the teleport never triggers. (Collision wasn't the cause: the foot Jackie is a
   fresh DES entity with collision on, and `promoteToCompanion` re-asserts collision-on defensively.)

5. **Bike braking.** Yes he can stop safely: at 40 m the drive command re-issues at `slowSpeed` (3 m/s),
   so by 30 m he's crawling and parks smoothly rather than slamming to a halt.

6. **Debug pings.** Both modes now log distance every **3 s** (`riding/sprinting/walking in... X m to V`),
   plus one-shot transition logs (easing off, downshift to walk, dismount, handoff).

- [ ] **TEST:** CET window → toggle FOOT/BIKE → "Test arrival now". FOOT: spawn ~50 m, sprint, walk last
      25 m, companion at ~5 m (no yank into V), grunt at 4 m. BIKE: rides in, eases at 40 m, parks ~30 m,
      sprints, same finish. Watch the 3 s distance pings in the console.
- ⚠️ Leftover legacy (harmless): `JL.arrival` table kept ONLY for `.seeded` (RNG flag used by
  navmeshArrivalPoint); the dismiss/hardReset clears of its dead fields are no-ops. Can be pruned later.

## 🆕 v0.52 — dinner picker polish (DEPLOYED, awaiting test, 2026-06-19)
- **Merged the picker into the accept node:** after Jackie's "had enough for one day", the venue picker shows
  immediately. **Raincheck is now an option IN the picker** (alongside the venues + "You pick, hermano.").
- **Only 4 random venues** shown per picker (`Config.date.venuesShown`, Fisher-Yates in `withDateChoices`;
  stable for the menu's lifetime since it builds once).
- **"You pick, hermano." → Jackie NAMES the spot:** `restaurants[].pickText/pickSfx`; `dine:random` prefers
  venues he can name. Wired: Lizzie's (`jl_1691270077089771520`), Afterlife (`jl_1790891785270616064`).
- **Removed "Gettin' one of my good feelings."** from the holocall greeting pool (`Config.callTree.ring`).
- **Arrival greeting = a real LINE now, not a grunt:** `arrivalGreetTick` used to play WWise bark *events*
  (`ono_jackie_greet`/etc., which sound like grunts). It now speaks a jl_ clip + subtitle from
  `Config.call.arrivalGreetings` via `pickArrivalGreetLine` (same no-repeat + 5-min cooldown; guards against
  talking over an open convo). Proximity barks still use the WWise events.
- Files: `config.lua` (restaurants pickText/sfx + `venuesShown`, merged `date.tree`, callTree pool,
  `call.arrivalGreetings`), `init.lua` (`withDateChoices` random-4, `findRestaurant` prefers nameable,
  `startDinnerWalk` speaks pick line, `pickArrivalGreetLine` + `arrivalGreetTick` speaks a real greeting).

## 🆕 v0.48 — Jackie hungry-hint + arrival greeting + seated line fix (DEPLOYED, awaiting test, 2026-06-19)
- **Jackie drops a hungry HINT himself:** new `jackieDinnerOfferTick` — while companion + dinner available
  (off the 24h cooldown), after a random in-game gap (`Config.date.jackieInvite`, **140–175 min**, near his max
  summon time) he just SAYS *"C'mon, let's go have some lunch."* — **no picker, no choices**; it nudges V to
  use her own invite. Set `jackieInvite.enabled=false` to revert.
- **Arrival no longer grunts — he GREETS:** `arrivalGreetTick` (was `arrivalGruntTick`) now plays a greeting
  from the full greet pool via `pickFreshGreet` — never the one used most recently, and not any greet used in
  the last **5 min** (`greetRepeatCooldown=300`). Proximity greets use the same no-repeat picker now.
- **Seated beat reworded:** `doneText` (said 2s after he sits at dinner) "Gettin' one of my good feelings." →
  **"Anyway, what's goin' on?"** (`jl_1878047791342612480`). That line was wrongly used as a v0.47 greeting.
- **`everywhere` greeting** 3rd line is now **"¿Qué onda?"** (`jl_2015561179233951744`).
- Files: `config.lua` (`doneText`, `jackieInvite` text/sfx + 140–175 min, `everywhere` pool, version 0.48),
  `init.lua` (`jackieDinnerOfferTick` speaks the line; `pickFreshGreet` + greet no-repeat state;
  `arrivalGruntTick`→`arrivalGreetTick`, `arrivalGruntPending`→`arrivalGreetPending`).

## 📝 Backlog — dialogue lines to wire (added 2026-06-19)
New line dump documented in `docs/conversations.md` §7–§8.1 (clips matched, Antonia's audio trims noted). To place:
- [ ] **Goodbyes** for phone + dismiss: rotate the **4** "Ahí luego, V." recordings + "Better get goin'" + "Hey V... keep an eye out".
- [ ] **Embers date (date 3)** — script written in `docs/conversations.md` §8.1. Needs: a completed-dinner **counter** (`JL.dinner.count`), **Embers coords** captured into `Config.date.restaurants`, per-venue seated-line override (orders Tequila Old Fashioneds), and the `embersOpen/embersPay/embersSplit` nodes.
- [ ] **Date 1** "I'm a bit light, can't pay you" (→ V "my treat") — first-dinner gag.
- [ ] **Afterlife date ACCEPT** line ("...Afterlife, here we come, baby!") when the picked venue is the Afterlife.
- [ ] Splice the bare "Nah"s with a warm follow-up (Misty/Sorry) so they're not abrupt.
- [x] Jackie can open a lunch invite himself ("C'mon, let's go have some lunch.") — done in v0.48.
- [ ] **Dinner cooldown REFUSE line** — "Got no time for this!" dropped (unsuitable); currently a placeholder
  (reuses the decline line "Why, what's the rush?"). Pick a proper "already ate today / not again" clip.
  NOTE (v0.58): the new 503-line pool is **thin on clean declines** (most "no" lines are quest-combat
  specific) — see `docs/VOICE_LINES.md` § Decline. Needs a targeted listen/search before this resolves.

## 🎙️ Voice bank refresh (777 → 1280 lines) — DONE (v0.56–v0.58, 2026-06-19)
WolvenKit WAV extraction (1282 clips) ingested. Full pipeline + conventions now in **`docs/VOICE_LINES.md`**.
- [x] **v0.56** — crosswalk the 777 via `lines.json` `vo_wem` → `tools/upgrade_audio.py` replaced every
  `jl_<id>.ogg` with the full-quality `jl_<id>.wav`; YML rewritten. 503 unknown clips staged in `new_lines/`.
- [x] **v0.57** — `tools/ingest_new_lines.py` copied the 503 into the tagger + stubbed `lines.json`
  (`source:"new_unscraped"`, keyed `new_<stem>`). Tagger gained NEW badge / editable transcript / "new only" filter.
- [x] **Transcripts** — `tools/whisper_transcribe.py` (Whisper "small", CPU) auto-transcribed all 505. ~90%
  accurate; **mishears names** (cabrón/chica/Misty/hermano) → always listen before wiring a line in.
- [x] **v0.58** — `tools/register_new_lines.py` renamed the 503 to `jl_<stem>.wav` and registered them in the
  YML → **all 1280 lines now playable from `config.lua`** via `sfx="jl_<stem>"`. Integrity verified (1281 unique
  keys, 0 missing files, existing 44 refs still resolve). New lines have **no String ID** → keyed by wem stem.
- The 2 `civ_low_*` voicemail clips are tagger-only (not in the audioware bank) — don't reference them.
- [x] **v0.59 — `tools/tag_lines.py`:** filename-derived `v_gender` (108 male-V + 1174 female-V) + flagged
  the **80-line V funeral/voicemail set** (`v_scene_jackie_default_*`) as `memorial` / `speaker:"V"`. Tagger
  gained V-gender dropdown + "memorial only" filter + V♀/V♂/MEMORIAL badges. `lines.json` documented as the
  canonical label DB the whole mod reads. See `docs/VOICE_LINES.md`.
- [x] **v0.60 — tagger rework (`tools/tag_usage.py` + `index.html`):** category dropdown replaced with the
  mod's real roles (greeting/accept/decline/bye/food/conversation/memorial/usable); play-chance % slider
  replaced with **never / very rare / sometimes / often** buttons (clicking *never* auto-marks tagged); deleted
  the "Where it fits" section + "partial" button; added **sneaky/professional** moods. `tag_usage.py` derives
  which lines are **wired in `config.lua`** (44, with role) + the `conversations.md` §4 **"usable" stash** (10)
  and writes `used`/`category`/`usable`/`seed_done` onto `lines.json`; the tagger shows **USED·\<role\>** /
  **USABLE** badges and pre-marks those 54 lines tagged on load (`seedTags`). Verified live.
  - [ ] **Re-run `tools/tag_usage.py` whenever you wire a new line into `config.lua`** (idempotent; un-marks removed lines).
  - [ ] The "usable" stash parse only covers `conversations.md` **§4**. If lines are stashed elsewhere (§5/§6 scene scripts), widen the parse or move them under §4.
- [x] **v0.62 — recover String IDs for the new pool (`tools/backfill_string_ids.py`):** the String ID *is*
  the wem hash in decimal — `string_id == int(<trailing hex token>, 16)`, verified **777/777** on the scraped
  lines. No WolvenKit/metadata/guessing needed. Filled `string_id` for all **505** new records (reference-only;
  sfx keys stay `jl_<stem>`). Idempotent; `--all` re-verifies the old 777. Documented in `docs/VOICE_LINES.md`.
- [ ] **Reunion scene (retrieval questline):** the 80 `memorial` lines are V calling Jackie's dead line
  ("So I went to your funeral", "my last call") — V-side audio, pick by player `v_gender`. Strong material
  for the retrieval/reunion beat. Not for Jackie's voice.
- [ ] **Backlog:** tag/curate the 503 in the tagger; wire chosen ones (see category picks in `docs/VOICE_LINES.md`).
- [ ] **(open, from v0.61 session)** Optional **SoundDB lookup helper**: now that every new line has its real
  `string_id`, we can fetch canonical subtitle text / scene context / quests for the new pool by querying
  SoundDB by String ID — replacing the ~90% Whisper guesses with CDPR-accurate metadata. Small `tools/` script
  (reuse `scrape_jackie.py`'s API client: `https://sounddb.zhincore.eu/v1`). Antonia hadn't decided yes/no —
  pick up next session if accurate transcripts for the new lines are wanted.

## 🆕 v0.47 — dinner dialogue refinements (DEPLOYED, awaiting test, 2026-06-18)
- **Invite question** (`Config.date.inviteText`): "Hey - you hungry?..." → **"Wanna get something to eat?"**
- **Accept line:** Jackie now answers the invite immediately with **"Yeah, had enough for one day, lemme tell you."**
  (open node of `Config.date.tree`). V then either picks a spot or rainchecks.
- **Decline ends earlier:** the venue picker moved to a new `venue` node, so picking *raincheck* (or the
  on-cooldown refusal) ends the talk **right after the question** — the restaurant list never shows.
- **Cooldown refusal moved up:** the "won't eat out twice a day" check now fires at the invite
  (`runCallAction "start_date"`), not after a venue pick. ~~"Got no time for this!"~~ **DROPPED** (unsuitable,
  Antonia) — `refuseText` is a **placeholder** ("Why, what's the rush?") until a real "already ate today"
  clip is picked from the refreshed bank (see Voice-bank backlog below).
- **"Don't come here often..."** dropped from the `everywhere` (companion/after-a-call) tree — it's a
  fixed-location greeting only now; replaced there with "Anyway, what's goin' on?".
- Files: `config.lua` (inviteText, refuseText, `date.tree`, `everywhere` pool, version 0.47),
  `init.lua` (`start_date` cooldown gate, removed the now-dead gate in `startDinnerWalk`).

## 🆕 v0.46 — 3-way arrival selector (safe/sprint/bike), earlier handoff + arrival grunt (DEPLOYED, awaiting test, 2026-06-18)
- **`Config.call.arrivalMethod`** (`"safe" | "sprint" | "bike"`) replaces the `arriveByVehicle` boolean.
  CET-window button now CYCLES safe → sprint → bike; "Test arrival now" fires the selected one.
  - **bike** = the OLD vehicle arrival, restored: `vehicleArrivalTick` phase (0) branches on `va.useBike`
    — bike+Jackie spawn behind V, mount, ride in (placing/driving phases + stuck failsafe + foot
    fallback), then sprint → walk → companion. "We'll nurse it back to health" (Antonia).
  - **sprint** = bikeless (v0.45): spawn directly at distance, sprint → walk → companion.
- **Earlier companion handoff for ALL THREE:** new `Config.call.companionDistance = 18.0` (was 6 for
  safe / 3 for sprint+bike). He stops the long solo walk-in at 18 m and just follows you.
- **Arrival grunt (ALL THREE):** `promoteToCompanion` arms `JL.summon.arrivalGruntPending`;
  `arrivalGruntTick` fires a one-shot `ono_jackie_bump` grunt once he closes to
  `Config.call.arrivalGruntDistance = 4.0` m. Cleared on dismiss.
- [ ] **TEST:** CET window → cycle method → "Test arrival now" for each. Confirm: companion at ~18 m,
      grunt at ~4 m, bike actually appears + rides in (the open question), no second Jackie.
- ⚠️ **CLEANUP DEBT (do soon):** the arrival section is now MESSY — two near-duplicate state machines
  (`arrivalTick` for safe vs `vehicleArrivalTick` for sprint+bike) with copy-pasted sprint/walk/handoff
  logic, plus ~6 bike helpers + a foot-fallback. Plan: unify the sprint/walk/handoff tail into ONE
  shared helper both ticks call, behind small distance accessors.

## 🆕 v0.45 — seat tuner FIX + seat-angle lock + collision status line (DEPLOYED, awaiting test, 2026-06-18)
> v0.45b correction: the first pass still didn't move him. THREE causes (see below, now all fixed).
- **Seat tuner did nothing — THREE bugs.** (1) `aiTeleport`'s `doNavTest=true` snapped any nudge to the
  nearest navmesh point. (2) The first fix made `placeAtExact` use the **TeleportationFacility ONLY**,
  which **no-ops on AMM/DES puppets** (the AITeleportCommand is the real mover) → he replayed the sit in
  place. (3) Teleporting the SAME frame as the workspot let it re-pin him at the old spot. **FIX:**
  `placeAtExact` now leads with `aiTeleport(pos, yaw, doNavTest=false)` (exact + actually moves him),
  facility as a 2nd write; and the sit is deferred in TWO steps (place → 0.4 s gap → workspot). The tuner
  re-seat also `stopWorkspotPose`s and waits 0.45 s for the release before teleporting (a teleport while
  he's pinned in the seat is ignored). Idle sit + dinner sit use the same place-then-gap-then-sit path.
- **Wrong seat ANGLE depending on arrival direction — FIXED.** The AMM workspot inherited his walk-in
  facing. Now the deferred sit carries the EXACT pos + yaw (`pendingPose.vec/.yaw`) and `placeAtExact`
  locks his facing the instant before the workspot plays → seat angle is deterministic from the waypoint
  yaw, same no matter where he came from. Tuner yaw slider widened to ±180° so you can spin him fully.
- **Collision STATUS line in the CET window:** `Collision  setting: ON/OFF  |  live on Jackie: …` shows
  the master-switch setting AND the live state on the entity (idle "OFF — deactivated ✓", dinner-seat, or
  "no idle Jackie spawned yet"), so you can confirm collision is actually deactivated.
- [x] **CONFIRMED WORKING (Antonia):** sliding/yaw move + spin him; tuned the noodle stools.
- **Noodle = ONE seat = the MIDDLE stool** `{ -1439.472, 1259.021, 23.090 }`, yaw -87.1 (two stools made
  him fidget/hop between them, so he stays on the middle one). The RIGHT stool `{ -1440.477, 1258.164,
  23.090 }` is kept as a DEPRECATED comment in `config.lua` for reference.
- **Tuner generalised to ANY sit venue (v0.45):** a **Venue picker** (only venues with a sit waypoint:
  noodle/misty/coyote/afterlife/ginger/lizzies) — picking one also Force-venues Jackie there — plus a
  **seat selector** (`< prev / next >`) for venues with multiple stools. Tuner now edits
  `Config.locations[key]`'s `seatIdx`-th sit waypoint; carries that seat's `poseAnim` (so Misty's deep
  chair tunes with the right anim); single-seat venues also move the anchor. `JL.tuner.key/seatIdx`.
- [ ] **TEST (other venues):** tuner → pick Misty/Coyote/etc → walk to him → tune → Print → send coords.

## 🆕 v0.45 — bikeless "SPRINT-IN" arrival + live method toggle (DEPLOYED, awaiting test, 2026-06-18)
**Goal (Antonia):** salvage the good details from the shelved vehicle arrival — sprint-first-then-walk
(`Config.vehicle.sprintToWalk = 25`) + the clean direct-at-distance spawn — into a usable arrival,
**skipping the bike spawn + mount**. Then expose an in-game toggle to A/B it against the safe walk-in.
- **`vehicleArrivalTick` is now BIKELESS** (`init.lua`): phase (0) skips `spawnDynEntity(bike)` + mount +
  drive entirely. It spawns Jackie DIRECTLY at the far navmesh point (clean dynamic-entity spawn — no
  spawn-pop near V, so none of the hide/teleport hack the safe walk-in needs), then drops straight into
  the existing refined `sprinting → walking → handoff` phases (sprint in, walk the last `sprintToWalk` m,
  promote to companion). The bike helpers (`mountAsDriver`/`driveBikeTo`/stuck failsafe/foot fallback)
  are LEFT IN but unreferenced — kept only for a future bike-ride revival.
- **`Config.call.arriveByVehicle`** now selects SPRINT-IN (true) vs SAFE WALK-IN (false); still defaults
  false. `Config.vehicle` trimmed: live knobs first (`spawnDistance`/`sprintToWalk`/`arriveDistance`),
  bike knobs flagged unused.
- **In-game toggle (CET window):** "Arrival method: SPRINT-IN / SAFE WALK-IN" button flips it live, plus a
  **"Test arrival now"** button that fires the selected arrival immediately (no holocall needed).
- [ ] **TEST:** open the CET window → toggle method → "Test arrival now" for each. SPRINT-IN: Jackie
      should appear ~80 m out, run in, downshift to a walk ~25 m out, become companion. SAFE WALK-IN:
      hidden spawn → teleport → jog in (unchanged). Confirm no second Jackie, no spawn-on-top-of-V.

## 🆕 v0.44 — Esc-menu "Go Home Jackie" recovery panel (MERGED to main, awaiting test, 2026-06-18)
- **NEW DEPENDENCY: Native Settings UI (`nativeSettings`)**, CET 1.18.1+. Adds an in-game
  **Esc → Settings → Jackie Lives → Recovery** page (see README requirements for the folder-name +
  load-order notes). Folder must be named exactly `nativeSettings`.
- **`hardReset()`** (init.lua): stops sit/lean workspots → `dismissAllJackies()` (AMM-wide despawn +
  orphan/duplicate clear) → wipes ALL newer transient state (idle wander/leave/pose/collision, dinner,
  secret cameo, call, branch/subtitle). Does NOT spawn (settings menu pauses the game → `onUpdate`
  frozen); primes `JL.timer` so the next unpaused `scheduleTick` re-places one clean idle Jackie at his
  scheduled spot. Player-facing panic button for a stuck/duplicated/missing Jackie.
- **`nsTick()`** registers the page from `onUpdate` (retried until `nativeSettings` is available, once),
  NOT `onInit` — CET loads `JackieLives` before `nativeSettings` alphabetically, so onInit `GetMod` is
  nil. Logs `…registered` / `…FAILED: <err>` / `…not found after retries`.
- [ ] **TEST:** reload/restart → console prints `[JackieLives] Native Settings panel registered`. Then
      Esc → Settings → Jackie Lives → Recovery → "Go Home". Confirm all Jackies vanish (incl. dupes), no
      errors, and a single clean Jackie returns to his scheduled spot. Try while summoned, idle, mid-sit.

### Problems & Resolutions (v0.44 Esc-menu)
- **THE root cause (v0.46 fix): our dupe-guard threw.** We called `nativeSettings.pathExists("/jackielives/recovery")`
  (a SUB-path) before the tab existed; the lib does `data[tabPath].subcategories[...]` and `data["jackielives"]`
  is nil → indexing `.subcategories` on nil **throws**. The throw was swallowed by `pcall(nsTick)` with
  `s.done` already true → silent: NativeSettings init line printed, but NO `[JackieLives]` line, no page.
  Fix: guard on the TAB path `pathExists("/jackielives")` only (the lib handles a missing tab there
  cleanly), wrapped in pcall. Lesson: `pathExists` is only safe on a sub-path once the tab already exists.
- **Menu showed empty ("No mods using native settings installed!") = OUR registration failed, not a
  NativeSettings install issue.** First build registered in `onInit` → `GetMod` nil (load order). Fixed
  with the `onUpdate` retry. Compounded by a **shared-deploy clobber**: a `main` deploy (feature absent)
  overwrote the test build in the game's CET mods dir, so the running mod had no menu code at all.
- **`GetMod("nativeSettings")` matches by FOLDER name** — a `CP77_nativeSettings-…` folder returns nil
  forever. Documented in README.
- **Spawn-while-paused** avoided by deferring re-placement to `scheduleTick` (the menu pauses the game).

## 🆕 v0.44 — REGRESSION FIXES + collision cleanup + arch docs (DEPLOYED, awaiting test, 2026-06-17)
**Context:** v0.43 was authored by 3 concurrent sessions editing `init.lua` at once (vehicle-arrival,
lipsync, dialogue/dinner — each logbook entry flags "a concurrent session owns X"). Two regressions/
unfinished bits surfaced; root cause = subsystems reaching into shared helpers.

- **BUG 1 — holocall: Jackie spawns in V's face / stands inside her.** Cause: the holocall routed to
  the **VEHICLE arrival** (`Config.call.arriveByVehicle = true`), which has been broken for ~6 versions
  (no bike appears) and falls back to a crude foot-spawn that lands him on V. The clean spawn-at-distance
  walk-in (`arrivalTick`) was unchanged + reliable but only used when `arriveByVehicle = false`.
  - **FIX:** `Config.call.arriveByVehicle = false` → holocall now uses the on-foot `arrivalTick` (spawn
    at 80 m, hidden, walk in, hand off). Vehicle arrival is **SHELVED** (documented, not deleted).
- **BUG 2 — dinner: Jackie won't go to his chair.** Shipped UNFINISHED (its own logbook entry: "OPEN:
  confirm the sit lands"). Causes: (a) collision never dropped for the dinner sit → chair blocked him
  from reaching the 2 m seat radius (my v0.43b guard had even disabled the narrow drop for companions);
  (b) sit anim played the SAME frame as the align-teleport (the float bug); (c) no reach timeout → silent
  give-up; (d) the would-be collision restore lived in `wanderTick`, which is dead while he's a companion.
  - **FIX (dinnerTick rework):** drop collision on entering `seating`; walk to seat; on reach **or**
    `seatTimeout` (12 s) snap onto the seat + **defer** the sit by `poses.delay`; restore collision when
    he stands; `promoteToCompanion` re-follows. Dinner now OWNS its collision end-to-end.
- **CLEANUP — collision ownership untangled.** Removed all collision toggling from the SHARED pose
  helpers (`tryWorkspotPose`/`stopWorkspotPose`/`wanderTick`). Now exactly three owners: IDLE →
  `applyIdleCollision()` at placement (`Config.idleNoCollision`); DINNER → `dinnerTick`; COMPANION →
  `promoteToCompanion()` forces collision ON (a follower must collide / not clip V). Dropped the unused
  `Config.poses.sitNoCollision` / `collisionRestoreDelay`. Moved `setNpcCollision` above
  `promoteToCompanion` (Lua scope: the companion path needs it).
- **DOCS — `init.lua` now opens with an ARCHITECTURE MAP** (each subsystem + its `JL.*` state) and a
  **COLLISION OWNERSHIP** map, so the next session knows which block owns what. `config.lua` collision
  section rewritten to match.
- [ ] **TEST:** (1) Call Jackie → he spawns far + walks in (no bike, not in V's face). (2) While he's a
      companion, invite him to dinner → he walks to the chosen bar, sits cleanly, clock resets, re-follows.

## 🆕 v0.43 — in-game SEAT TUNER + sit-time collision drop (DEPLOYED, awaiting test, 2026-06-17)
> ⚠️ v0.44 SUPERSEDED the collision parts below — the "sit-time drop" + master-switch guards were
> removed and replaced by the per-subsystem ownership model (see v0.44). The SEAT TUNER is unchanged.
- **SEAT POSITION TUNER (debug window).** New collapsing panel "Seat position tuner (Noodle bar)" with
  live **X / Z** sliders (+ Y and yaw for free) as **offsets** from the captured noodle seat. "Live"
  re-seats Jackie ~0.25 s after you stop sliding (debounced full stop→teleport→deferred-sit, so it
  goes through the same path as the schedule). Fine ±0.02 nudge buttons for X and Z. "Print coords ->
  config.lua" logs the config-ready line + live-patches the in-memory `noodle` anchor AND its sit
  waypoint so he keeps sitting right for the rest of the session. (`tunerInit/Coords/Apply/Print` +
  `JL.tuner` in init.lua; targets `Config.locations[JL.tuner.key]`, key = "noodle".)
  - **Workflow:** Force venue -> Noodle bar → walk to him → open the tuner → slide X/Z live → "Print
    coords" → paste the numbers to Claude to bake into config.lua permanently.
- **MASTER COLLISION SWITCH (v0.43b) — `Config.idleNoCollision = true` (default ON).** Idle Jackie's
  collision is dropped the moment he's PLACED at a location (`applyIdleCollision()` in `wanderTick`
  step 0, before the snap-teleport) and stays off his whole stay — so chair/stall geometry can't block
  him from reaching a seat coordinate OR shove him out of it. **Flip switch in the mod window**:
  "Idle Jackie: collisions OFF" (applies live to the spawned entity). Also applied in `returnToPost`.
  Trade-off: V can walk through idle Jackie while it's on. Companion Jackie unaffected.
- **Sit-time drop (v0.43, narrow fallback).** `Config.poses.sitNoCollision` still drops collision just
  before a SIT anim and restores it after `collisionRestoreDelay` (2 s) — but ONLY when the master
  switch is OFF (guarded in `tryWorkspotPose`/`stopWorkspotPose`/`wanderTick` so the two never fight).
  Same `NPCPuppet:DisableCollision/EnableCollision` trick (`docs/spawn_at_distance_research.md`).
- [ ] **TEST:** at the noodle bar with the switch ON, confirm Jackie reaches + sits the stool cleanly
      (no chair-block, no shove-out). Then slide X/Z in the tuner and send me the printed coords.
- ⚠️ **Note:** `DisableCollision`/`EnableCollision` are `pcall`-guarded — if the method isn't on the
      puppet in this build it silently no-ops. The window shows live "collision: OFF/on" next to the
      Wander line so you can confirm the toggle is actually taking.

## 🆕 v0.43 — DINNER OUTING rework (take Jackie out to eat) (DEPLOYED, awaiting test, 2026-06-17)
Concurrent-session (dialogue) work; touches `Config.date` + the dinner state machine only. While Jackie
is your companion the talk menu offers a dinner invite → V picks a **specific restaurant** → he walks
there with you, takes his seat, and his companion clock resets. He STAYS your companion the whole time.
- **5 restaurants**, each pointed at the real bar/stall coords+yaw reused from `Config.locations`:
  noodle bar, **Redwood Market** (the "noodle place" stall), **Afterlife** (barstool), **Ginger Panda**
  (bar), **Lizzie's** (rear bar). Options are auto-injected from `Config.date.restaurants` (any with `pos`).
- **Map waypoint** (white dot) via `Game.GetMappinSystem():RegisterMappin` (CustomPositionVariant) + a
  **blue on-screen OBJECTIVE** ("Dinner with Jackie - meet him at X") shown until V reaches the spot.
- **Arrival → seat:** V within `seatTriggerRadius` (12 m) → Jackie drops follow, walks to `seatReachRadius`
  (2 m), snaps onto his coord+yaw, plays the **sit anim** (`tryWorkspotPose`), waits `sitWaitSeconds` (2 s),
  says ONE line — that's the **full companion-clock reset**, rate-limited to **once / 24 in-game hours**.
- **Walk away → re-follow:** V > `getUpRadius` (10 m) from seated Jackie → he stands, says "Why, what's the
  rush?", and `promoteToCompanion` re-adds the follower role. `JL.summon.active` stays true throughout; the
  auto-leave is paused for the whole outing. Banter on the walk/arrival is **fully disabled** (Antonia).
- Phases `walking→seating→seated` in `dinnerTick` (moved below the pose/move helpers it needs); HUD in
  `drawDinnerObjective`; entry from the `dine:<key>` action in `runCallAction`.
- [ ] **TEST:** pick each restaurant → blue objective + white dot → he peels off and sits at the bar →
      2 s → line + reset → walk off → he gets up + follows. Confirm he never despawns.
- [ ] Verify the **mappin** draws (console `Dinner: waypoint set (mappin id=…)`; if `id=nil`, tweak the
      create call) and whether a **route line** shows or just the dot.

## 🆕 v0.41 — dismiss→return-to-post, dwell tune, sit-float fixes (DEPLOYED, awaiting test, 2026-06-17)
- **Dwell middle ground:** 45-150s → **30-90s**.
- **RETURN-TO-POST on dismiss (`Config.transitions.returnRadius = 100`).** Dismissing companion Jackie
  while he's within 100 m of the venue the schedule currently wants him at → he drops the follower role,
  the SAME entity is handed back to the idle system, and he walks to the nearest waypoint and re-joins
  the cycle (no despawn/respawn). Farther/off-schedule → normal walk-away-and-despawn. (`returnToPost`
  in init.lua, wired into the "dismiss_walkaway" dialogue action.) NOTE: there's only ever ONE Jackie
  entity — idle and companion are two SYSTEMS that hand the same entity back and forth, not two Jackies.
- **Sit "in the air" fixes:** (a) the pose was played the same frame as the snap-teleport, so AMM spawned
  the sit prop at his OLD spot → now DEFERRED `Config.poses.delay` (0.5s) via `JL.idle.pendingPose`.
  (b) added per-waypoint `poseOffset = {x,y,z}` to nudge him onto the real seat (AMM sit is freestanding).
- **BARSTOOL sit:** default sit anim → `sit_barstool__2h_on_lap__01` (most of his chairs are stools).
  Per-waypoint `poseAnim` override added; **Misty's deep chair** uses `sit_chair__2h_on_lap__01`.
- **Exact sit coords:** Afterlife bar-RIGHT `{ -1449.437, 1012.129, 17.357 }` (left-bar sit removed);
  Misty deep chair `{ -1541.289, 1194.016, 16.600 }`.
- **Exit waypoints added:** Afterlife `{ -1471.229, 1038.869, 22.661 }`, Misty `{ -1547.112, 1185.049, 16.493 }`,
  Noodle `{ -1440.553, 1258.332, 23.099 }`. ⚠️ Misty/Noodle exits are OUTSIDE the venue — TEST whether he
  actually walks there or the world-streaming/navmesh blocks it (timeout despawn is the fallback).
- **SECRET NAP CAMEO (easter egg):** `Config.secret` — 20% chance per night he's leaning at
  `{ -1470.154, 1201.503, 19.084 }` during the 00:00-06:00 sleep window (`secretWantKey`, re-rolls nightly).
- [ ] **TEST:** dismiss near a venue → he walks back + goes idle (cycles); dwell feels right; sit no longer
      floats (deferred). If still off the chair, tune that waypoint's `poseOffset` (z down to lower him).
- [ ] **FOLLOW-UP (real chair sit):** AMM sit is freestanding (invisible chair). For him to use the ACTUAL
      chair (like the scripted bar scene) we'd find the chair DEVICE at runtime + play ITS workspot — the old
      `sitNearest` idea. Bigger task; tune `poseOffset` first and see if freestanding-aligned is good enough.

## 🆕 v0.41 — arrow-key fix (RELEASED edge) (DEPLOYED, awaiting test, 2026-06-17)

**ARROW NAV BUG — ROOT CAUSE FOUND + FIXED.** Antonia: ↑/↓ navigate the choice picker on the FIRST layer
only; after V speaks → Jackie replies (layer 2+) the arrows die and she falls back to the `-` key.
- **Cause (from the v0.40 console capture):** on the first layer the arrows arrive as BUTTON_PRESSED, so the
  `OnAction` handler's just-pressed gate caught them. On DEEPER layers the game's dialog/popup input context
  delivers the SAME actions (`up_button`, `UI_MoveUp`, `popup_moveUp`, `popup_navigate_up`, `navigate_up`)
  ONLY as **BUTTON_RELEASED** (pressed=false) — so the just-pressed gate threw them all away. (The `-` key
  kept working because it's a hard CET binding, context-independent.)
- [x] **FIX (v0.41):** navigation now fires on the **RELEASED edge** (`actionReleased` helper = IsButtonJust-
  Released + typed-RELEASED fallback) — the one edge present in every input context. A single press emits
  several matching names in one frame, so a **0.12 s debounce** (`JL.lastCycle`) collapses the burst to one
  move. Confirmed deeper-layer names added to `CYCLE_UP/DOWN_ACTIONS`. SELECT (F) stays on the press edge
  (already worked on every layer). `cycleDebug` LEFT ON for this verification round.
- [x] **CONFIRMED WORKING (Antonia, v0.41).** Arrows navigate every layer.
- [x] **v0.42 cleanup:** arrows were INVERTED → flipped (UP=`move(-1)`, DOWN=`move(1)`). Dropped the `-`
  cycle key (`jl_cycle_choice` removed) + turned `cycleDebug` off. Box hint now "↑/↓ move, F confirms".

## 🆕 v0.42 — arrow polish + PROXIMITY BARKS (DEPLOYED, awaiting test, 2026-06-17)
- [x] **Arrow direction flipped** + `-` key dropped + `cycleDebug` off (see above).
- [x] **Proximity greeting bark.** Idle (non-companion) Jackie at a location: V within **greetRange** (6 m
  default) → ONE random greeting (`ono_jackie_greet`/`curious`/`additional`), then `greetCooldown` (120 s).
- [x] **Bump grunt.** V within **bumpRange** (1.2 m default) → grunt (`ono_jackie_bump`), `bumpCooldown` (8 s).
- [x] **All-in-init.lua** (`proximityBarkTick`, lazy `JL.bark` state) to avoid colliding with the other
  session's config edits. **Live tuning sliders** in the CET window (greet/bump range + cooldowns, a
  V-distance readout, and Test buttons). Promote `JL.bark` → `Config.bark` once distances are locked.
- [ ] **TEST (Antonia):** stand near idle Jackie → greet fires once on approach; walk into him → grunt.
  Tune the 4 sliders until the feel is right, then tell me the values to bake in.
- [ ] **Recruitment limits (CORRECTED SPEC 2026-06-17).** Builds on existing `Config.companion`
  (`maxGameHours`) + `Config.date` (dinner reset). Rules:
  - **Daily budget: 6 in-game h total** as companion per day (NEW — track a per-day accumulator, reset at
    midnight). **Per-call cap: 3 in-game h** max per single "come on the job" recruitment (replaces the flat
    6h single-stint timer). Refuse the gig in the recruit convo once the daily budget is spent.
  - **Timer expiry → he leaves**, EXCEPT **in combat**: prolong the timer, he stays till combat ends; **20 s
    after combat ends** he then leaves. (Need a combat-state check — `GetPlayer():IsInCombat()` or NPC combat.)
  - On leaving: say a **departure line**, then **walk away** (reuse the send-off walk-away exit path).
  - **Dinner ALWAYS fully resets the daily budget** (until midnight) — clears the spent daily total, not
    just +hours (`Config.date` currently does +`resetCompanionHours`; change to a full reset of the 6 h
    budget). This applies WHENEVER dinner is accepted; the **walk-away intercept** (V catches him as he's
    leaving on timer-expiry and asks him out) is just one notable moment where it matters.
  - **15% chance** he says the hunger HINT line on timer-expiry departure (drop a dinner hint):
    `jl_1834512408575406080` "C'mon. I'm fuckin' starved." (alt `jl_1904096844380655616` "Man, I'm starvin'…").
  - Dinner ("ask him out") **always** allowed. <3
  - **Departure-line pool (what we have — bank is thin on V-facing goodbyes; he barely says bye in canon):**
    `jl_1155727714874494976` "Time we were on our way, mamita." · `jl_1967553783536623616` "Better get goin'." ·
    `jl_1993514843414274048` "Thanks, I will! V, you take it easy, OK? Rest up a bit." (+ the 2 hunger hints above).

## 🆕 v0.39 — recruit-in-place fix + REAL sit/lean + tuning (DEPLOYED, awaiting test, 2026-06-17)
Fixes from Antonia's v0.38 in-game test, plus sit/lean cracked.
- **RECRUIT-IN-LOCATION FIXED (the big one).** The gig dialogue ended but nothing flipped idle Jackie
  to a companion — scheduleTick/wander kept owning him. Added `recruitIdleJackie()`: the location gig
  choices now carry `action = "recruit_here"` → hands his LIVE entity from the idle system to the summon
  system, `promoteToCompanion()`, and releases the schedule/wander grip WITHOUT despawning (same entity,
  no pop). So "Let's go/roll" at a venue now actually makes him follow.
- **REAL SIT/LEAN (`Config.poses`).** Cracked via AMM's own workspot pipeline (read AMM
  `Modules/anims.lua`): `AMM.Poses:PlayAnimationOnTarget(target, anim)` → `Game.GetWorkspotSystem():
  PlayInDeviceSimple + SendJumpToAnimEnt`. On a sit/lean waypoint he now plays `sit_chair__2h_on_lap__01`
  / `stand_wall_lean180__2h_on_wall__01` (Man Average, amm_workspot_base); `StopInDevice` gets him up
  before he walks / is recruited / despawns. Fully guarded → falls back to standing if AMM Poses is
  unreachable. Swap anim names in `Config.poses` for a different look.
- **Wander wait longer:** dwell 15-45s → **45-150s** (he was moving too often).
- **F-talk range 4 → 6 m** (easier to catch a moving NPC; longer dwell helps too).
- **Real appearance names wired:** `jackie_welles_default` / `_default_collar_down` /
  `__q005_suit` / `__q000_lizzies_club_no_jacket`.
- **Coyote exit moved** to Antonia's final despawn spot `{ -1247.138, -985.136, 16.027 }` yaw -77.3.
- **Misty re-captured** (2 waypoints: anchor + near the small cats).
- [ ] **TEST:** (1) Talk to him at a venue → "Let's go" → he should become a follower (no 2nd Jackie).
      (2) Sit/lean waypoints (noodle chair, Coyote lean spots, bar sits) → he actually sits/leans, and
      gets up when he moves. (3) Longer dwells; outfits correct per venue; he despawns at the new Coyote spot.


## 🆕 v0.38 — 14h schedules + WALK-AWAY built + vehicle-arrival fresh-respawn fallback (DEPLOYED, awaiting test, 2026-06-17)

**Schedules (`Config.daySchedules`):** longer stays — active days now ~**14h present** (4h home + 6h sleep);
3-4 stops/day. Swapped Afterlife (was A1) and Misty (was A2) so **Afterlife is an EVENING stop** (A2
19:00-23:30). **active3 is busy** (Noodle 4 + Misty 3 + **Afterlife 3** + Coyote 4 -> bed). Lizzie's still
only active1's 21:00-23:30 (closed before 21:00). Verified 00-24 coverage, no gaps:

  | Day-type | Stops (hours) | Home | Asleep | Present |
  |----------|---------------|------|--------|---------|
  | active1  | Noodle 5 · Misty 6 · Lizzie's 2.5 · Coyote 0.5 | 4 | 6 | 14 |
  | active2  | Redwood 5 · Ginger 4 · Afterlife 4.5 · Coyote 0.5 | 4 | 6 | 14 |
  | active3  | Noodle 4 · Misty 3 · Afterlife 3 · Coyote 4 | 4 | 6 | 14 |
  | quiet    | Misty 4 · Coyote 3 | 11 | 6 | 7 |
  | gone     | — (out of town) | — | — | 0 |

**WALK-AWAY (BUILT, `Config.transitions.departOnFoot`):** when his block ends and you're nearby, idle
Jackie no longer pops out — he walks to the venue's **exitWaypoint** (Coyote = upstairs / his way home;
Lizzie's = outside) or, at venues with no exit captured, just **away from you** (`awayPoint`), and despawns
when he reaches it, leaves your range (+5 m), or `leaveTimeout` (20 s) passes. `idleLeavingTick` drives it;
wander + scheduleTick yield while `JL.idle.leaving`. (The 50 s transit gate + walk-IN arrival are still the
remaining V1.0 pieces — arrival is currently instant-spawn when you're near the new venue.)

**VEHICLE-ARRIVAL FRESH-RESPAWN FALLBACK (BUILT, `Config.vehicle.fallbackSeconds = 40`):** the bike ride-in
often breaks. If no companion handoff within **40 s** while still on the bike (placing/driving),
`vehicleArrivalFootFallback` **despawns the bike AND Jackie**, respawns him **FRESH ~40 m out** on the
navmesh, and drops into the existing on-foot **sprint -> walk -> companion** phases. Fires once; the 120 s
maxSeconds teleport remains the last resort.

- [ ] **TEST:** (1) Stand near a venue, "Cycle day-type" / fast-forward past his block end -> he walks off
      to the exit (Coyote upstairs) and vanishes, not a pop-out. (2) Call Jackie (vehicle arrival) and if the
      bike stalls, ~40 s in he should despawn + reappear ~40 m out and jog in. (3) active days feel ~14h present.

## 🆕 v0.36 — 5 SHUFFLED day-types + per-location OUTFITS (BUILT, awaiting test, 2026-06-17)
Jackie no longer visits every location every day, and dresses for the venue.

**Day rotation (`Config.daySchedules` + `Config.dayBag`, logic in init.lua):** 5 day-types in a SHUFFLE
BAG — each new in-game day pops the next, reshuffling when empty, so every 5-day cycle uses each type
exactly once (no skips) in random order.
- `active1` (afterlife/noodle/coyote) · `active2` (misty/redwood/ginger) · `active3` (afterlife/ginger/
  coyote) — full days, each only 2-3 DIFFERENT locations; across the three, all six spots are covered.
  Each keeps 6h asleep + 8h home = 10h out.
- `quiet` — only Misty's + El Coyote + lots of home (mostly unavailable).
- `gone` — out of town, unavailable the entire 24h.
- **Day rollover = game-hour WRAP** (`ensureDayTemplate`: current hour < last → passed midnight → pop
  next day-type). Chosen over reading a "day" field because `getGameHour` is the confirmed-working time
  signal on this build, and time only ever moves forward (sleeping/fast-travel included). RNG seeded at
  `onInit`. CET window shows `Day-type: <key>` + a **"Cycle day-type"** debug button to jump days instantly.

**Per-location outfits (`Config.locations[*].appearance`, threaded through `ammSpawn(flag, appearance)`):**
Jackie idle-spawns wearing the venue's outfit — `default` (noodle/coyote), `suit` (misty = his "date"
look), `Lizzies_club_no_jacket` (ginger), `default_collar_down` (afterlife/redwood). Summon/arrival use
`Config.defaultAppearance` ("default").
- ⚠️ **These appearance strings must match AMM's EXACT names for Character.Jackie.** If an outfit doesn't
  change in-game, open AMM's appearance list for Jackie and correct the names in `Config.locations`.
- Note: Lizzie's Bar itself isn't a captured location yet — the `Lizzies_club_no_jacket` outfit currently
  only appears at Ginger Panda. Capture Lizzie's coords later to add it.

- [ ] **TEST (Antonia):** (1) use "Cycle day-type" to walk through all 5 — confirm active days hit only
      their 2-3 spots, `quiet` is sparse, `gone` never spawns him. (2) Sleep past midnight a few times →
      console logs `New day -> schedule '<key>'`, and over 5 days each type appears once. (3) Check each
      location shows the right outfit; report any that don't so I fix the appearance name.

## 🆕 v0.35 — FREE-ROAM WANDER + full schedule (BUILT, awaiting test, 2026-06-17)
Idle Jackie now **walks around** his scheduled location instead of standing on one spot, and the daily
schedule is rebuilt around Antonia's **6h asleep + 8h "at home" (off-map)** unavailability rule.

**Wander (`Config.wander` + `wanderTick` in init.lua):**
- Each location has `waypoints` (pos/yaw/pose, optional per-wp `dwell={min,max}`). State machine per idle
  spawn: **place** him on a random waypoint (AI-teleport, settle 0.6 s) → **dwell** a random `dwellMin..Max`
  (15–45 s) → walk (`sendMoveToPoint`, the same passive-NPC `AIMoveToCommand` the walk-in/walk-off use) to a
  **random OTHER** waypoint (`pickNextWaypoint` never repeats the current → no back-and-forth pacing) →
  dwell → repeat. Re-issues the move every `repath` (2.5 s); `arriveTimeout` (30 s) failsafe. Single-waypoint
  locations (noodle, misty) just plant him there. He stays PASSIVE throughout (not a follower).
- **pose = sit/lean is DATA ONLY for now.** `applyIdlePose` snaps him onto the exact spot facing the captured
  `yaw` (so a "lean" point faces the wall), but a **real sit/lean WORKSPOT animation is still a TODO** (the
  hard part — see the chair-sit note below). "stand" and "sit"/"lean" look identical at this stage.
- CET window shows `Wander: <phase>  wp <cur>/<tgt>` while idle for debugging.

**Schedule (`Config.schedule`):** 14h unavailable (6h sleep + 8h home), 10h spread across the map so you
bump into him at varied times:
`00–02 Afterlife · 02–08 ASLEEP · 08–12 Noodle · 12–16 HOME · 16–18 Misty's · 18–20 El Coyote · 20–24 HOME`.

**Coords:** all of session-3's captures formatted into `docs/captured_positions.md` and wired into
`Config.locations` with waypoints — `coyote` (6 pts) + `afterlife` (5 pts) now have real coords (were nil);
new `ginger` (Ginger Panda, 7 pts incl. the "Any Austin" circle) + `redwood` (Redwood Market, 4 pts) added
but NOT in the daily schedule yet (swap in freely).

- [ ] **TEST (Antonia):** be near a scheduled location in its time window → Jackie spawns, walks between the
      waypoints, dwells, faces the right way at each. Watch the CET `Wander:` line. Report if he gets stuck,
      teleports oddly, or a waypoint is off (clipping/floating).
- [ ] **NEXT — real sit/lean workspot** in `applyIdlePose` (TODO marker in init.lua). Folds together with the
      old `sitNearest` chair-sit task below. Needs in-game workspot-API testing, not built blind.
- [ ] **NEXT — Ginger Panda ordered-loop** ("Any Austin" easter egg): walk waypoints 2→7 in order, loop ~3×,
      then long dwell at the bar. Add a `mode = "loop"` branch to `pickNextWaypoint`/`wanderTick`.

This closes the session-2 carryovers: **misty now has a schedule slot** (16–18), and **coyote/afterlife
coords captured + placed**. (Chair-sit + follow/dismiss-via-dialogue still open.)

## 🆕 v0.33 — dismiss-by-dialogue + centered picker + arrow-key cycling (DEPLOYED, awaiting test, 2026-06-16)
Three follow-ups after the v0.32 location-trees test (cooldown + everywhere confirmed working in-game).

1. **"Send Jackie off" dialogue option (walk away → despawn at 30 m).** New `Config.dismiss` block. While
   Jackie is your **companion**, `withCompanionExtras()` appends a `dismiss_walkaway` choice to EVERY talk
   node (so it's always reachable; the everywhere-tree cooldown is also bypassed while he's active). Picking
   it ends the talk → `runCallAction("dismiss_walkaway")` → `startLeaving()`:
   - Drops his follower role the same way AMM does (`GetAIRole():OnRoleCleared(h)` + `isPlayerCompanionCached
     = false`) so the companion AI stops pulling him back (this was the key — a still-following NPC would never
     reach the despawn distance).
   - Plays a parting VO line (`jl_1155727714874494976` "Time we were on our way, mamita.").
   - `sendMoveToPoint()` (new generic AIMoveToCommand to an arbitrary point) walks him to `awayPoint()` — a
     spot past V→Jackie direction. `leavingTick()` re-issues every 1.5 s and **despawns at `despawnDistance`
     (30 m) or after `maxSeconds` (30 s)**. Instant `dismissJackie`/`dismissAllJackies` hotkeys now also clear
     the leaving state.
   - [ ] **TEST:** summon Jackie → talk → pick "Head home, Jackie" → he says his line, walks off, vanishes ~30 m out.

2. **Dialogue picker centered + lower.** `drawDialogueBox()` now reads `ImGui.GetDisplaySize()` and sets the
   box X to screen-centre (`(sw-W)/2`) and Y to `sh*0.46` (a bit below mid-screen; was a fixed 340,360).
   Falls back to 1920×1080 if display size can't be read.
   - [ ] **TEST:** the choice box sits centered, slightly low.

3. **Arrow-key cycling by default (no binding).** OnAction hook now moves the highlight on `CYCLE_UP_ACTIONS`
   / `CYCLE_DOWN_ACTIONS` (candidate CNames for ↑/↓). `Config.dialogue.cycleHint` = "Up/Dn".
   - ⚠️ **CAVEAT (honest):** CET can't read raw keys during gameplay (overlay closed), so this relies on the
     game emitting an *input action* for the arrows — and arrows may be UNBOUND in the gameplay context. So
     `Config.dialogue.cycleDebug = true` logs every action name pressed while the box is open (`[JackieLives]
     CYCLE action: <name>`). The bound **"Jackie dialogue: next choice"** input (Antonia's `-`) still works as
     the guaranteed fallback.
   - [ ] **TEST + REPORT:** open a Jackie convo, press ↑/↓, read the CET console. If `CYCLE action:` lines
     appear with the arrows → paste the exact names so I lock them (and turn cycleDebug off). If NOTHING logs
     on arrows → they emit no action on this build; fallback plan = bind arrows once in CET, or switch cycle to
     a key that fires in gameplay (mouse-wheel / a movement key).

## 🆕 v0.33b — holocall-summon REVERT + walk-in speed boost (DEPLOYED, 2026-06-16)
**Problem (Antonia's test):** holocall summon regressed — after hang-up Jackie spawned **visibly in V's face,
then vanished**. Cause = the unfinished spawn-at-distance *polish pass* still active in `Config.call`:
`hideOnSpawn=true` (ToggleVisuals is one-way-broken on this build → the reveal never fired → "vanished"),
`spawnBehind=true` (couldn't see him), `spawnDistance=60` (render-edge). **Resolution = pure CONFIG revert to
the test-3 known-working values — no change to the shared `arrivalTick` code (other session owns it):**
- `spawnDistance` 60→**40**, `spawnBehind` true→**false**, `hideOnSpawn` true→**false**, `arriveDistance`
  1.6→**3.0**. (`arrivalTick` already honors `== false` on those flags, so OFF = old visible-in-front walk-in.)
- Flags KEPT in config (default off) so the polish can return once ToggleVisuals + the far navmesh point are fixed.
- **Speed boost (new):** `Config.call.approachBoostSeconds=15` + `approachBoostMovement="Sprint"`. New
  `arrivalMoveType()` returns the boosted tier for the first 15 s of the walk-in (timer `JL.arrival.walkStart`),
  then settles to `approachMovement` ("Run"). NOTE: engine uses discrete Walk/Run/Sprint tiers, so this is
  ~1.5× "Run", not a literal 1.5× multiplier (no continuous speed lever via AIMoveToCommand).
- [ ] **TEST:** call Jackie → ask onto gig → hang up → he spawns ~40 m in FRONT, visible, sprints in ~15 s, settles.

**v0.33c (DEPLOYED, 2026-06-16):** `hideOnSpawn` CONFIRMED working → back ON. Added 3 live A/B toggle
buttons to the CET window ("Arrival test modes") that mutate `Config.call` at runtime: (1) spawnBehind
in front/behind, (2) spawnDistance cycle 20/40/60/80/100, (3) arriveDistance ON 3.0 m / OFF (walks into V).
Labels show current state. → Antonia dials in the best combo, reports the 3 values, then bake as defaults.
NOTE: handoff at `handoffDistance` (6 m) promotes him to companion mid-walk, so `arriveDistance` < 6 has
little visible effect unless we also gate the handoff behind it (offered).

## 🆕 v0.33d — arrival polish: 80 m, jog, flash fix, versioned deploy (DEPLOYED, 2026-06-16)
- `Config.version = "0.33d"` added; `deploy.ps1` greps it and prints `=== Deploying JackieLives v0.33d ===`
  (+ closing line); `init.lua` onInit now logs `Loaded v<version>` instead of a stale hardcode.
- `spawnDistance` 40→**80 m**; `spawnBehind` default **true** (confirmed good; button still toggles).
- Speed: Sprint felt too fast → `approachBoostMovement` "Sprint"→**"Run" (jog)**, so he jogs the whole way
  (discrete Walk/Run/Sprint only; no continuous multiplier).
- **Spawn-in-face FLASH fixed.** Root cause: AMM spawns him 1 m in front of V and sets `spawn.handle` several
  frames late (Cron poll), and the old hide fired ONCE — a `ToggleVisuals(false)` before visuals attach
  no-ops, so he popped visible. Fix in `arrivalTick`: resolve the entity early via `spawn.entityID`
  (`Game.FindEntityByID`), attempt an immediate same-frame hide, and **re-apply the hide every tick until
  reveal**; placeAt delay 0.8→0.5 s. If a 1-frame blip ever remains, the bulletproof option is spawning at
  the 80 m point directly (other session's spawn-at-distance territory).
- [ ] **TEST:** call → gig → hang up → he spawns hidden behind V at 80 m, jogs in, no visible pop near V.

## 🆕 v0.32 — LOCATION-BASED branching talk trees (DEPLOYED, awaiting test, 2026-06-16)
Face-to-face talk (press **F** on Jackie) now picks a branching tree based on **where he currently is**,
instead of one linear banter. New `Config.locationDialogue` with 5 trees:
- `noodle` / `coyote` / `afterlife` / `misty` — each ~5 nodes, location-flavored (food / Mama Welles +
  drinks / merc-legends bittersweet / Misty + spiritual). Each opener uses a random `jackiePool` line for
  variety; choices branch to a "side gig" or a warm farewell. Repeatable (no cooldown).
- `everywhere` — the **BACKUP**, used whenever he's NOT at a named place (summoned/following, or an
  unscheduled/`test` spot). Deliberately short: **2 choices, short voice lines**. Carries
  `cooldownSeconds = 60`: finishing it once marks it **DONE** and starts a 60 s cooldown; pressing F again
  inside that window **just grunts** (no dialogue). After 60 s the short exchange is available again.
- [x] All 20 voice-line IDs verified present in `audioware/JackieLives/index.json` (real Jackie VO).
- [ ] **TEST in-game (Antonia):** at each location press F → correct themed tree; away from any place → the
      short backup; finish backup, press F within 60 s → grunt only; after 60 s → backup returns.

How it works (init.lua):
- `currentTalkTree()` reads `JL.idle.locationKey` → `Config.locationDialogue[key]`, else `everywhere`.
- `Branch.kick()` now returns a bool (started?) and enforces the DONE cooldown via `JL.talkDone[key]`.
- F hook reordered: try `Branch.kick()` first; only grunt (`talkToJackie`) if no convo started. This also
  fixes the old grunt+dialogue audio overlap on the first F press, and is what makes the cooldown "just
  grunt" behavior fall out for free.
- Conversation-end stamps `JL.talkDone[key]` when the finished tree had `cooldownSeconds`.

Problem & resolution:
- *Problem:* needed Jackie's spoken lines to match real VO but be location-specific. *Resolution:* kept
  Jackie's spoken lines generic-but-fitting (real verified `jl_<id>` clips) and put all the location flavor
  in the **silent V choice text** (no V audio exists, so choices are free to say anything).

## 🆕 SPAWN-AT-DISTANCE WALK-IN — holocall arrival rework (DEPLOYED, awaiting test, 2026-06-16)
Replaces the old "spawn 1 m from V → naive teleport forward" arrival (which kept dumping Jackie at V's
face) with a navmesh-validated spawn-at-distance + walk-in. Research in `docs/spawn_at_distance_research.md`.
New `Config.call` knobs: `spawnDistance` (60), `spawnBehind` (true), `hideOnSpawn` (true),
`approachMovement` ("Run"), `arriveDistance`, `handoffDistance` (6), `maxWalkSeconds` (90); `spawnDelay` 5→2.5.
Flow (in `init.lua` `arrivalTick`, all `[JackieLives] Call:` logged):
1. **Navmesh point** — `navmeshArrivalPoint()` sweeps 12 headings × 3 distances, snapping each candidate via
   `NavigationSystem:GetNearestNavmeshPointBelowOnlyHumanNavmesh` (returns Vector4 directly → clean CET call,
   no out-param/enum). Falls back to the plain forward point if no navmesh hit (logged).
2. **Passive spawn** — `ammSpawn(0)`. **KEY FIX:** `ammSpawn` now forces `amm.userSettings.spawnAsCompanion =
   (flag == 1)`. It was only ever set TRUE and never reset, so every "passive" arrival after a companion summon
   was still a companion → follower role → **catch-up teleport to V's face**. THAT was the teleport-to-face bug.
3. **Place + walk** — **TELEPORT FIX (after test 2):** `GetTeleportationFacility():Teleport` was confirmed to
   silently no-op on the fresh NPC (console: "after place, Jackie is 1.9 m from V" despite a good 40 m navmesh
   point). Switched to `AITeleportCommand{ doNavTest=true }` via the AI controller (`aiTeleport()`), verified on
   a LATER tick (0.7 s — reading position the same frame as Teleport returns the stale spot). Then
   `sendMoveToPlayer()` = `AIMoveToCommand` to V's CURRENT coords, **re-issued every 2 s** (Antonia's design —
   manual follow, no companion semantics → no teleport).
4. **Handoff** — when within `handoffDistance` (or after `maxWalkSeconds`), `promoteToCompanion()` gives him the
   real follower role (combat + auto-follow). Teleport powers only return when he's already next to V.
- [x] **WORKING (test 3, 2026-06-16).** AI-command teleport fixed the placement: Jackie spawns ~40 m away and
      a passive NPC DOES obey `AIMoveToCommand` (walks in to V). Confirmed the whole pipeline.
- [x] **Polish pass (DEPLOYED, awaiting test):** (a) **spawn BEHIND V** — `navmeshArrivalPoint` now bases the
      sweep on V's BACKWARD direction + a random angle within the rear 180° arc (`Config.call.spawnBehind`,
      RNG seeded per session). (b) **60 m** (`spawnDistance` 40→60). (c) **hide the spawn pop** —
      `Config.call.hideOnSpawn`: `setVisible()` = `entity:ToggleVisuals(false)` the instant his handle exists,
      reveal at distance after the teleport verifies. Console logs `Call: Jackie hidden during placement.` /
      `Call: Jackie revealed at distance.` — if those are MISSING, `ToggleVisuals` isn't the right method on this
      build → fall back to an invisibility status effect.
- [~] **Speed FIX (DEPLOYED, awaiting test):** he walked slowly despite `approachMovement = "Run"`. Cause =
      assigning a raw STRING to the command's `movementType` enum field silently falls back to Walk(0). Added
      `resolveMoveType()` (string → `moveMovementType` enum, `Enum.new` fallback, then string) and use it in
      both `sendMoveToPlayer` (walk-in) and `sendWalkToPlayer` (companion follow). If he STILL walks, the AI is
      clamping a passive NPC to walk → fallback: spawn companion + raise TweakDB `catchUpTeleportDistance`
      (companions run to keep up), or set an alerted move state.
- [~] **Stop-distance FIX (DEPLOYED, awaiting test):** he clipped INTO V. `arriveDistance` 3.0→**1.6** (walk-in
      MoveTo stop) + new `followDistance` **1.6** applied as a companion `AIFollowTargetCommand` in
      `promoteToCompanion` (the handoff at 6 m means the COMPANION drives the final approach, so its follow
      spacing is the real lever for not crowding V).
- [ ] Plan B if a passive NPC ever stops obeying moves: spawn companion + raise TweakDB
      `IdleActions.MoveOnSplineWithCompanionParams.catchUpTeleportDistance` (default 20) to suppress the teleport.
- [ ] Once reliable: dial `spawnDistance`/`approachMovement` to taste (40 m Run ≈ 12 s; 100 m is render-edge).

## ✅ v0.34a — LIP MOVEMENT / talk animation (DONE, shipped 2026-06-17). Full writeup: `docs/lipsync.md`.
**Problem:** mouth frozen while speaking — our `AudioSystem:Play` / Audioware audio carries no facial data,
so the engine's viseme system never animated his face. (Real CP2077 lipsync is JALI-baked per line; no
public tool.) **Outcome:** his face rig is intact (probe proved it), so it was a *driver* problem.
- [x] **Probe (CET reflection + live components)** → `facial_methods.txt`. Confirmed face_rig /
      man_face_base_animations / entAnimationControllerComponent / scnVoicesetComponent all present.
- [x] **Route A (push facial anim events) — FAILED;** **Route B (workspot) — ABANDONED** (callable but no
      usable conversation-workspot path; see `docs/route_b_workspot_plan.md`).
- [x] **Route C — `PlayVoiceOver` is THE driver (= AMM "NPC Talk").** A voiceset **context** token (e.g.
      `"greeting"`, NOT raw event names) plays real voice + real lipsync. Preferred path for greetings/reactions.
- [x] **SHIPPED: talking-face flap** for our Audioware lines (no VO event → can't drive visemes). While a
      Jackie line plays, shuffle AMM Expressions Overhaul "Talking" faces (`AnimFeature_FacialReaction`,
      **category 7, idle 231..266**, 242 skipped) every ~0.9s, then `ResetFacial`. Engine in `init.lua`
      (`flap`/`startFlap`/`flapTick`), hooked into `speakJackieLine` + `dialogueTick`; `flapTick` in onUpdate.
      **New dependency: AMM Expressions Overhaul (Nexus 20108).** Test bench: standalone `mod/JackieLipsync/`.
- [ ] **Next (chosen direction):** map dialogue beats → real VO voiceset contexts where they exist (true
      lipsync + voice, game assets); keep the cat-7 flap only for bespoke lines with no matching context.
- [skip] amplitude/volume→jaw (engine viseme pipe only runs inside VO playback) · hand-authored `.scene` lipsync.

## 🆕 v0.28 — HOLOCALL "Call Jackie onto a gig" (BUILT, awaiting in-game test, 2026-06-16)
Reuses the working voiced dialogue engine + AMM summon AS a phone call — **not** the native phone UI,
so **no death flag / contact unlock is needed** (see "death flag" note below). New in `config.lua`:
`Config.call` (ringSeconds/ringEvent/spawnDelay/spawnDistance) + `Config.callTree` (the call conversation).
Flow: **"Call Jackie (holocall)"** button / `jl_call` hotkey → "Calling Jackie..." ring (~2.5s) → he picks
up and the SAME styled choice box runs `callTree` → choosing **"Got a gig. You in?" → "See you soon."**
(choice carries `action = "summon_arrival"`) ends the call → **`spawnDelay` (5s) later** Jackie spawns
`spawnDistance` (18m) ahead of V and **walks in** (AMM companion AI paths him).
- [x] **First in-game test (Antonia) done.** Bugs found + FIXED in v0.28a (deployed): (a) Jackie spawned
      ON the player — teleport-to-distance silently failed (likely `GetWorldForward` nil → fell back to V's
      exact spot, and/or AMM repositioned him a frame after our teleport). Fix: robust `arrivalPoint()` (3
      facing fallbacks + never returns V's spot + logs the point) and teleport ~0.8s AFTER spawn so AMM is
      done. (b) Subtitles didn't show during the call — null speaker on a phone call (no Jackie entity);
      fix: carry the line on the player. (c) V's chosen line too brief → `Config.dialogue.choiceHold = 2.5`s.
- [ ] **RE-TEST the call** after restart: spawn-at-distance + walk-in, call subtitles, 2.5s V line. If he
      still ends up near V, read the console `[JackieLives] Call: arrival point via ...` line — tells us which
      facing source was used + the computed point (debug built in). Leash-snap is the fallback hypothesis.
- [x] **NATIVE PHONE UI — SOLVED via probing (2026-06-16).** Full investigation in `docs/native_phone_probes.md`.
      No HolocallSystem class; calls run through `PhoneSystem:TriggerCall(mode, false, callId, true, phase,
      false,false,false, visuals)`. Recipe: mode `Video(2)`, callId CName `jackie`/`jackie_dead`, phases
      `IncomingCall(1)`/`StartCall(2)`/`EndCall(3)`. In-game test findings: `IncomingCall` on `jackie` plays the
      game's OWN canned call; **`StartCall` opens a silent, persistent see-through holocall window** (our canvas);
      `EndCall` hangs up cleanly. We can fire TriggerCall ourselves (Codeware reflection confirmed PhoneSystem
      reachable via scriptable-systems container).
- [x] **v0.29a first integrated attempt FAILED** — opening `StartCall` and keeping it up *while* the choice
      box ran left the call stuck (input/UI conflict; convo never finished -> no `EndCall` -> phone blocked).
      Likely worsened by a residual stuck call from earlier raw-CONNECT tests. Reverted; added a **Force hang up**
      button + watchdog so a call can never stay permanently stuck.
- [ ] **v0.30 — IMMERSIVE LINK + line diversity, TEST.**
  - **Player phone-call hijack:** Observe `PhoneSystem:TriggerCall`; when the PLAYER calls Jackie (IncomingCall
    on a 'jackie' call id, not one of our own — re-entrancy guard `JL.call.selfTriggering`), route into our
    flow (`onPlayerCalledJackie`). `Config.nativeCall.hijackPlayerCalls`. So calling Jackie from the in-game
    phone now triggers our conversation. TEST: in-game phone -> call Jackie -> our convo runs.
  - **Random Jackie lines:** nodes can carry a `jackiePool` (array); engine picks one at random. callTree
    ring/howbeen/gig now have voiced pools seeded from the 777-line scan.
  - **Line scan:** `tools/voice-tagger/classify_lines.py` buckets all 779 playable lines into greeting/
    farewell/agreement/howdoing -> `classify_out.json` (gitignored; verbatim transcripts). Curated the best
    generic ones into the pools. OFFER: add the 4 bins to the tagger UI (index.html) for manual curation if
    Antonia wants finer control.
- [ ] **v0.29b — Antonia's flow, TEST.** "Call Jackie (holocall)" = native **RING (IncomingCall ~2s)** ->
      **STOP (EndCall)** to abort the canned native call -> **CONNECT (StartCall)** empty transparent window ->
      our branching voice convo runs over it -> at the end of any strand a **random V farewell** (12 in
      `Config.callFarewells`, text-only) -> **hang up (EndCall)** -> "Let's do it." spawns him to walk in.
      Toggle `Config.nativeCall.useNativeWindow`. STILL the open risk: does the connected window steal the
      choice-box input? If the convo can't be navigated, that's the blocker to solve next.
- [ ] **Polish: avatar thumbnail.** CONNECT window is see-through (avatar not loaded). Try the RING-first load,
      or render Jackie's portrait ourselves, so the window looks like a real call.
- [ ] Later: real native holocall (portrait/video) = separate large WolvenKit `.scene`/contact task (Tier 2/3).

> **"Death flag" investigation (answered):** the native holocall is driven by quest `.scene`/`.questphase`
> resources — it can't be triggered with custom audio from CET Lua. Existing mods only convert holocalls→
> audiocalls (nexus 9422) or do text-SMS via CET JSON (cyberscript77 wiki). Flipping Jackie's "dead" fact would
> only change how the native contact *renders*; it would NOT make our custom voiced dialogue play through the
> native phone. So for the MVP the death flag is moot — our call "goes through" because it's our own UI.

## ✅ CURRENT STATE — v0.27 (CONFIRMED in-game, 2026-06-16). Full history: `docs/logbook.txt`.
Conversation system is END-TO-END working from pure CET Lua + AMM + Audioware (no WolvenKit yet):
- [x] **Real bottom SUBTITLES** — fixed via `ToVariant({line}, "array:scnDialogLineData")` (CET couldn't
      infer the array type). Show for F-talk and dialogue.
- [x] **777 lines play as Jackie's real voice** (Audioware; Opus→Vorbis). `jl_fallback.wav` safety net.
- [x] **Branching dialogue** — F starts it: Jackie speaks (voice+subtitle) → custom **game-styled choice box**
      (name tag left w/ red frame, vertical choices, solid yellow selection bar; colors #73eff0/#4d1505/
      #f8db4b/#743a39). Cycle key (bound to "-") moves highlight, F selects; V's pick shows ~1s then his reply.
      Box draws during gameplay and survives closing the CET overlay.
- [x] Custom CET ImGui HUD during gameplay is VIABLE (key unblock). Highlight-bar-growth bug fixed
      (text-width Selectable, no AlwaysAutoResize).
### Next priorities (in order)
1. **WolvenKit HQ audio** — Antonia installs WolvenKit; I batch-extract the game's own VO (`vo_wem` paths in
   lines.json) → wav → drop into the bank under the SAME `jl_<string_id>` names (pure drop-in). Step list in chat/logbook.
2. **Write real dialogue content** into `Config.dialogueTree` (data-driven; the engine is done).
3. Session-2 carryovers: give `misty` a schedule slot; chair-sit at noodle bar; follow/dismiss-via-dialogue.
4. (Cosmetic, low pri) cut-corner frames on the box — needs manual polylines, skipped for now.


## VERSION CONTROL / GITHUB (2026-06-16, session 2)
- [x] **Dedicated git repo created** inside `Cyberpunk_modding/` (was wrongly rooted at parent
      `Projects/` — an empty stray init that would have published all research; removed it).
      Repo-local identity `Antonia <schakka83@gmail.com>` (global config unavailable). 2 commits.
- [x] **`.gitignore` hardened for public release.** Excludes CDPR audio (`*.ogg/.wav/.wem`,
      `voice-tagger/audio/`), verbatim transcript dumps (`lines.json`, `index.json`), the ffmpeg
      binary, chat history, and `.claude/settings.local.json`. Repo is ~594 KB of pure source.
- [x] Added `LICENSE` (MIT, code only), `ASSETS_NOTICE.md`, top-level `README.md`, `docs/GITHUB.md`.
- [ ] **Antonia: create the PUBLIC repo on github.com** (empty, no README/license), then we run
      `git remote add origin <url>` + `git push -u origin main`. Steps in `docs/GITHUB.md`.
- [ ] After first push: regular workflow is `git add -A` → `git commit -m "..."` → `git push`.

## SESSION 2 (parallel edit, 2026-06-16) — MERGED into live `mod/JackieLives/`
> Session 2 staged its edits in a throwaway `working_copy_session2/`, then merged the cleanup +
> captured coords surgically into the live files (which the main session had advanced to v0.26 with
> new ISOLATED-UI-TEST picker styles). Working copy deleted after merge.

- [x] **CET window cleanup (MERGED).** Removed confirmed-done test/debug buttons from the "Jackie
      Lives" ImGui window: *Run diagnostics*, the whole *Native choice BOX experiment* block (Probe
      API / Test show box / Hide box + look-box checkbox), the *Audioware PIPE TEST* button, and the
      whole *Jackie voice* block (dropdown + Play on Jackie/Random + Play-on-V debug + Play typed
      event). **KEPT the ISOLATED UI TESTS block** (Antonia is actively iterating picker styles
      V1/V2/V3 there). Kept: Summon/Dismiss, Force main-quest, Capture position, Dialogue buttons,
      Enable schedule. (Orphaned helpers `probeChoiceBoxAPI` / `audiowareProbe` / `playVO` /
      `playRandomJackieEvent` left defined — harmless.)
- [x] **Captured schedule positions** (Antonia walked them in-game). Durable record:
      **`docs/captured_positions.md`**. Also applied to `working_copy_session2/config.lua`:
      - `misty` = Misty's Esoterica `{ -1541.072, 1195.238, 15.869 }` yaw 50.9 — **replaces Vik/Vic** as a destination.
      - `noodle` = Noodle bar `{ -1441.064, 1257.748, 23.090 }` yaw -87.1 — has a **chair** (`sitNearest = true`).
- [ ] **Give `misty` a schedule slot** in `Config.schedule` (currently captured but not placed in
      the daily timeline — noodle/coyote/afterlife/asleep already fill 24h). Decide which block Misty's takes.
- [ ] **Chair-sit at the noodle bar.** On idle-spawn at a location with `sitNearest = true`, find the
      nearest seat workspot and make Jackie sit. Feasibility: AMM can pose/sit NPCs and Codeware exposes
      the workspot system; the hard part is locating the nearest *seat* entity reliably. Approach to try:
      `Game.GetSpatialQueriesSystem()` / target nearby `Devices`/`furniture` or scan for a chair record
      near `loc.pos`, then drive the sit via AMM's animation/pose API. Needs in-game testing — not built blind.
- [ ] **Idle Jackie must not be a follower** at scheduled spots. ALREADY satisfied: `scheduleTick`
      spawns with the passive flag (`ammSpawn(0)`). Confirm visually after merge.
- [ ] **Follow-on-dialogue:** "go a job" / "let's hang out" choices flip idle Jackie → companion.
      Hook into the existing `Branch`/`summonJackie` companion path. Not built.
- [ ] **Dismiss dialogue:** a conversation option that sends companion Jackie back to idle/schedule
      (reuse `dismissJackie`, but keep him in the schedule rather than fully despawning). Not built.

## v0.24 (DEPLOYED, awaiting test) — feedback pass after v0.23 in-game test
v0.23 results: audio plays (quality poor -> WolvenKit HQ next); branching works after binding a cycle key,
Jackie responds. Issues fixed/changed in v0.24:
- [x] **Choice box = custom ImGui box** (was the native hub, which rendered choices side-by-side as F/R/1
      input prompts). Now a styled floating box: speaker name on top, choices in a VERTICAL column,
      highlighted row in YELLOW (matches docs/dialogue_picker_design.png). Drawn during gameplay.
- [x] **Removed number/Choice2-3 selection** (R/1 were bound elsewhere, didn't work). Selection is now ONLY:
      cycle key (bound to "-") moves highlight + F selects. Box shows a hint "[ - ] next  [ F ] select"
      (Config.dialogue.cycleHint). NOTE: CET can't hard-set a default binding in code; "-" is just the hint
      label - Antonia binds "Jackie dialogue: next choice" herself (she used "-").
- [x] **V's chosen line now shows as a subtitle for ~1s before Jackie replies** (Branch.confirm -> pendingAt).
- [~] **Subtitles STILL in the blue notification field, not the bottom band.** v0.22's `UIGameData.ShowDialogLine`
      push is failing -> falls back to the on-screen msg. v0.24 adds an ERROR LOG ("SUBTITLE push FAILED ...
      Error: ...") so Antonia's next test reveals the exact cause; fix definitively after. Mechanism is
      confirmed correct (Audioware uses it in Codeware.reds) - it's a CET construction detail.
- [ ] **WolvenKit HQ audio (NEXT, Antonia will install + I drive the batch).** Replace the re-encoded
      website .ogg with the game's own VO (extract .wem from opuspaks via WolvenKit -> wav; drop into the
      Audioware bank under the SAME jl_<string_id> names = manifest needs no change). lines.json has every
      vo_wem path. Step list given in chat.

## CONVERSATION BUILD — 4-step plan (Antonia, 2026-06-16, mod at v0.19)
Box rendering CONFIRMED. Now: from box -> linear conversation, step by step (each needs an in-game test).
- [~] **Step 1 (v0.19, DEPLOYED - awaiting test): make "[F] Talk" box PERMANENT.** Flipped
      `config.talk.useChoiceBox = true` so the box is now look-driven (shows when looking at Jackie in
      range, hides on look-away) instead of the one-shot "Test show box" button. Added `config.talk.boxRefresh`
      (re-assert heartbeat, 1.0s) so it survives if the game clears the blackboard while looking.
- [ ] **Step 2: pressing F LAUNCHES the dialogue box** (integrated system + blackboard; one option only,
      no conversation logic yet). The look-prompt vs the F-launched box are two states.
- [x] **Step 1 CONFIRMED in-game (v0.19): box persistent + grunt on F. Perfect.**
- [x] **Audioware PIPE CONFIRMED (v0.21): beep test plays; ver 1.9.2; manifest loads.** ROOT CAUSE of the
      earlier silence: the scraped `.ogg` are **OPUS** codec, which Audioware (kira/Symphonia) can't decode,
      so the manifest registered 0 ids ("Registry error: not found"). Fixed by converting to Ogg Vorbis.
- [~] **Steps 2-4 BUILT & DEPLOYED (v0.23) - AWAITING ANTONIA'S TEST.** All four pieces below shipped:
  - **(A) Subtitles -> real bottom band.** Was rendering in the blue notification field (SimpleScreenMessage).
        Now uses the NATIVE subtitle path `UIGameData.ShowDialogLine` / `HideDialogLine` (the exact route
        Audioware uses; see r6/scripts/Audioware/Codeware.reds). `showSubtitle/hideSubtitle/showDialogueText`
        in init.lua; falls back to the on-screen msg if `scnDialogLineData` can't build on this build.
  - **(B) 777 lines CONVERTED.** `tools/convert_audio.py` (uses a portable ffmpeg auto-downloaded to
        `tools/ffmpeg/`) re-encodes all 777 Opus `.ogg` -> Ogg **Vorbis** in `audioware/JackieLives/`
        (jl_<string_id>.ogg, ~24 MB) and regenerates the manifest (779 entries) + `index.json`
        (string_id -> {event,text}). `deploy.ps1` pushes the bank with `/PURGE`.
  - **(C) Fallback WAV.** `1155727714874494976.wav` ("Time we were on our way, mamita.") shipped as
        `jl_fallback.wav`, registered `jl_fallback`. Jackie lines fall back to it if their clip won't play.
  - **(D) BRANCHING dialogue box.** `Config.dialogueTree` (open -> howbeen/gig/bye). Jackie speaks a node's
        line (voice+subtitle), then a multi-choice native hub appears; choices are SILENT text (so missing V
        audio is moot). Selection: **F confirms the highlighted row** (reliable); bind "Jackie dialogue: next
        choice" (registerInput `jl_cycle_choice`) to move the highlight; Choice2/3 keys also select if the
        build fires them (every action is logged while a menu is open to discover the real CNames).
        CET window: "Play branching dialogue" + "Play test dialogue (linear)" buttons.
  - **OPEN QUESTION for the test:** does the multi-row hub render all choices, and does moving the highlight
        + F feel right? If native nav doesn't work, the bindable cycle key is the guaranteed fallback. If we
        want true native scroll-nav, that's the redscript route (deferred).

### !! FUTURE QUALITY MARKER (Antonia, 2026-06-16) !!
Replace the website-scraped `.ogg` (re-encoded Opus->Vorbis, slightly compressed) with the GAME'S OWN
FULL-QUALITY audio. Each line in `tools/voice-tagger/lines.json` carries `vo_wem` (e.g.
`base/localization/en-us/vo/jackie_q005_*.wem`) - extract those `.wem` via WolvenKit, convert (vgmstream),
and drop them into the Audioware bank under the SAME `jl_<string_id>` names (manifest already keyed that way,
so it's a file swap). Locate per line via string_id -> vo_wem. NOT NOW.

## NEXT SESSION — START HERE (handoff 2026-06-16, mod at v0.16)  [full history: docs/logbook.txt]
v0.15 F-trigger CONFIRMED working by Antonia. Recorder removed (code/window/hotkeys/config all gone).
Captured test coord saved: config.locations.test. v0.16 box probe ran -> first type guesses were WRONG;
decompiled scripts gave the REAL names; v0.17 (deployed) uses them - awaiting Antonia's box test.

### Choice-box authoritative facts (from CDPR-Modding-Documentation/Cyberpunk-Scripts, decompiled):
- The interactions UI controller (interactionsUI.script) registers a blackboard LISTENER on field
  `UIInteractions.InteractionChoiceHub`; on change -> `OnUpdateInteraction(Variant)` casts to
  `InteractionChoiceHubData` and builds the box. (It also listens to `VisualizersInfo` for the active
  world visualizer - OPEN QUESTION: is that anchor required for the box to appear?)
- `InteractionChoiceHubData` = { id:Int32, flags:EVisualizerDefinitionFlags, active:Bool, title:String,
  choices:array<InteractionChoiceData>, timeProvider }
- `InteractionChoiceData` = { inputAction:CName, rawInputKey:EInputKey, isHoldAction:Bool,
  localizedName:String, type:ChoiceTypeWrapper, data:array<Variant>, captionParts:InteractionChoiceCaption }
- v0.16 probe (her build) confirmed: blackboard fields `ActiveChoiceHubID` & `DialogChoiceHubs` exist;
  engine types `gameinteractionsvisListChoiceData` & `gameinteractionsChoiceCaption` construct, but
  `gameinteractionsChoiceHubData` does NOT (wrong name). The import-only engine wrappers are
  `DialogChoiceHubs{ choiceHubs:array<ListChoiceHubData> }` / `ListChoiceData` (the `vis` family).
- v0.17 approach: build `InteractionChoiceHubData` + push to `UIInteractions.InteractionChoiceHub`.
  If it renders -> iterate (add caption if row is blank). If not -> the box needs the visualizer anchor
  => pivot to WolvenKit NIF fixed-spot (Antonia's coord idea) or keep the working F+VO talk.
- [x] **BOX WORKS (v0.17, CONFIRMED in-game 2026-06-16).** "Test show box" renders a real native prompt
      "[F] Talk" via pushing an `InteractionChoiceHubData` to `UIInteractions.InteractionChoiceHub` - NO
      visualizer anchor needed, NO WolvenKit. v0.13's "impossible" box is solved from pure CET Lua. Pressing
      F plays the grunt (our OnAction hook), but the box's OWN choice-selection isn't routed yet - next polish
      if we keep it. The box label came through with just `localizedName` (no caption struct needed).

### BUILD NEW DIALOGUE + PHONE CALL — plan & progress (Antonia's new targets, 2026-06-16, full autonomy)
RESEARCH VERDICT: (1) NO native "play dialogue line by string ID" exists (confirmed across sources) - barks
are WWise events, dialogue lines are not, so you can't convert one to the other. Reusing his EXACT line
audio needs WolvenKit scene authoring OR **Audioware playing an audio file we ship** - and we ALREADY have
his `.ogg` for all 777 lines (scraper). So his real voice is reachable WITHOUT WolvenKit. (2) Dialogue
STRUCTURE (trees/choices/subtitles/facts) is very doable in CET - **Cyberscript** (cyberscript77, CET-based
JSON quest/dialogue engine) proves it; we build a lean Jackie-specific version instead of taking that dep.
3-PHASE PLAN:
- [x] **Phase 1 (v0.18, DEPLOYED - awaiting test): dialogue runner.** Pure CET, no WolvenKit. Scripted
      V<->Jackie exchange: each line = on-screen subtitle (speaker + text); Jackie's lines also fire a WWise
      voice event for presence. Data in `config.testDialogue` (includes "So let's do our thing."). CET window
      button "Play test dialogue" (summon Jackie first for his voice). This is the seed dialogue tool.
- [ ] **Phase 2: REAL voice.** Add Audioware (1 dependency) + a `voFile` per line -> play his exact scraped
      `.ogg` so he speaks the actual words (not a bark). Mostly Claude-drivable (we have the audio already).
      Quality is the website .ogg (slightly under the game .wem) but it's his real voice saying the line.
- [ ] **Phase 3: PHONE CALL (target 1).** Wrap a conversation as a holocall. Sub-parts:
      - Re-enable Jackie's CONTACT + VIDEO (Antonia: dead-Jackie call shows logo not video) -> hunt the
        "Jackie dead" fact/flag and override it; CET-testable (set facts, inspect contacts).
      - Arrival on the job: spawn at the edge of the rendered area + companion walk-to-V (feasible via our
        existing AMM summon at an offset position). BIKE arrival = vehicle AI + mount = hardest, DEFER.
      - Response line "So let's do our thing." (ID 1762127358882361344) plays via Phase-2 audio.
      - Frameworks seen: "Phone Extension" (text msgs only), "Holocalls to Audiocalls", Cyberscript phone
        conversations (text-style). None turnkey for a VO holocall -> likely our own thin layer + Audioware.
State: voice playback WORKS (Route A, his `ono_jackie_*` events; `ono_jackie_greet` confirmed on Jackie).
Talk = look at Jackie within 4 m -> weighted grunt, NATIVE on-screen message prompt "Talk to Jackie [F]".
**v0.15 (NEW, awaiting Antonia's test): real `F` trigger with NO binding** — instead of binding F (CET
can't, game reserves it), we `Observe('PlayerPuppet','OnAction')` and react when the game's own Interact
key is pressed while looking at Jackie. "=" CET fallback still bound. If F doesn't fire: set
`config.talk.logActions = true`, press F near Jackie, paste the `[JackieLives] OnAction:` lines (gives the
exact action CName) -> add it to `INTERACT_ACTIONS` in init.lua. These are the next builds:

- [~] **(TOP) Route (b): real "Talk" BOX — v0.16 ships a SAFE CET-Lua PROBE first (awaiting test).**
      RESEARCH VERDICT (2026-06-16): no public mod renders a script-pushed choice box — every "talk to NPC"
      mod (Talk to Me, Responsive NPCs, the AI ones) uses input+VO (WE HAVE THIS) or the phone UI. The
      reliable real box = **Native Interactions Framework**, but that's a WolvenKit ASSET workflow (projects/
      props/world placement), best at a FIXED spot — heavy, GUI-bound, not cleanly Claude-drivable. The one
      untried cheap path: push a `gameinteractionsChoiceHubData` to the **UIInteractions blackboard** and let
      the game's own UI controller render it (CET can set blackboard variants; this is data-push, NOT the
      v0.13 widget-attach that's impossible). v0.16 does this pcall-safe + a **"Probe API"** button that logs
      which interaction structs/blackboard fields really exist this build. Test: CET window -> "Probe API"
      (paste console), then "Test show box" while near Jackie. If it renders -> iterate the box. If not ->
      decide: WolvenKit NIF fixed-spot box (Antonia's coord idea, done legit) vs. keep the working F+VO talk.
      (decompiled scripts at codeberg adamsmasher/cyberpunk for exact ChoiceHubData fields if needed.)
- [ ] **Immersive SUMMON via PHONE CALL (replace the CET summon).** Call Jackie on the phone ->
      dialogue pops with options **"How are you doing?"** and **"Need some help with a job."** -> on the job
      option he **spawns nearby and walks to V (companion)** = our existing summon-as-companion path.
      - Bug to fix: when Jackie's dead, calling him shows only his **logo, not his video** in the phone UI.
        Defer; likely the "Jackie is dead" fact/flag — try disabling/overriding it so his contact + video work.
      - Response line for the job call (use once SENTENCE playback works): **"So let's do our thing."**
        String ID **1762127358882361344** (Quest · Spoken · quests q005_06b_the_chip, q005_06d_saburo_av).
      - This needs the phone/contact system (research how to add a callable contact + a choice hub) AND
        ties into the 777-sentence playback problem for his spoken responses.

## NOW (2026-06-16 cont.)  [see docs/logbook.txt for full history]
- [~] **Recorder v0.10 also caught NOTHING (2026-06-16, counter 0, jackie filter on AND off).** So the
      subtitle hook didn't fire either. We have NEVER confirmed CET `Observe` fires at all in this install.
      LOW PRIORITY NOW — the scraper catalogue already solves line *identification* (777 lines + String IDs),
      so the recorder is optional. To resume debugging we need ONE datum: the exact `Recorder hook
      registered: true/false on ...` console line (true = registered but not firing -> subtitles off / wrong
      method for v2.3; false = wrong class name). Next attempt should register at onInit + first prove
      Observe works on a known-good scripted method.
- [x] **Jackie line catalogue + audio — DONE (scraper).** `tools/voice-tagger/scrape_jackie.py` pulled
      all **777** of Jackie's lines (transcript + String ID + real `.ogg`) from the SoundDB API into the
      tagger. NOTE: those `.ogg` are for the TAGGER ONLY (auditioning lines on the phone) — NOT for in-game
      playback (we'd use her own installed full-quality audio for that).
- [~] **PLAYBACK — Route A WORKS for Jackie's VOICE EVENTS (v0.11, deployed).** Jackie has ~25 `ono_jackie_*`
      WWise events (greet, laughs, curious, efforts, pain, death...) + a few `vo_*jackie*` — his OWN events,
      so `AudioSystem:Play` sounds on him (same mechanism as the V grunt, but his bank). Added a "Jackie
      voice" dropdown + Play/Random/typed buttons; the look-at "Talk to Jackie" key now pulls from real
      event pools. List in `config.jackieEvents`. -> Antonia to confirm in-game (summon Jackie, Play on Jackie).
- [ ] **PLAYBACK (still open) — the 777 full dialogue SENTENCES.** These are dialogue String IDs, NOT WWise
      events, so AudioSystem:Play can't play them. Options: (A) native "play line by String ID" via the
      dialogue/voiceover/scene system — research (not yet found a clean call). (B) extract HER own `.wem`
      (full quality, same bytes the game uses) + play via Audioware. Decide once Route-A voice events are
      confirmed working. (Do NOT use the website .ogg for playback - those are tagger-only.)
- [ ] **VOICE-TAGGER — PAUSED (Antonia will run it in a NEW session).** Goal for that session: get it
      working **on her Android phone WITH audio**. Current blocker: opening `index.html` via `file://` can't
      `fetch` lines.json or load `audio/` -> falls back to the 5-line sample with no audio. Fix for phone:
      **Netlify Drop** (drag the whole `tools/voice-tagger` folder, incl. the local `audio/` — it's
      gitignored but present after running the scraper -> public https URL that works on Android with audio).
      Audio is confirmed working when SERVED (verified locally); the only issue is delivery to the phone.
- [ ] Antonia: capture coords (noodle MB8 / El Coyote Cojo / Afterlife) -> config.locations -> schedule
      then places idle Jackie at his spots.
- [ ] Later: real main-quest detection; single-instance enforcement; retrieval quest (Tier 2).

## Confirmed setup facts
- Platform: **Steam**. Build: **Patch 2.3 / 2.31** (Oct 2025). Core mod stack supports it.
- Mod manager: **Vortex**. Installed versions: RED4ext 1.30.0, redscript 0.5.31, CET 1.37.1,
  TweakXL 1.11.3, ArchiveXL 1.26.8, Codeware 1.20.3, AMM 2.12.5.
- Mod dev: source in `mod/JackieLives/`, deploy with `deploy.ps1` (auto-finds Steam install). Fast loop:
  deploy → CET overlay "Reload all mods" → load save (no exe restart needed).
- **Jackie's spawn record = `Character.Jackie`** (pinned in `config.jackieRecord`).
- Game-hour read works via the v0.3 method probe; schedule shows correct state (confirmed hour 4 = asleep).

## Setup (Tier 0 — environment)  → details in docs/SETUP.md
- [ ] Phase 0: stop auto-updates, back up saves, make test save.
- [ ] Phase 1: Vortex + Nexus account, manage Cyberpunk 2077.
- [ ] Phase 2: RED4ext → redscript → CET → TweakXL → ArchiveXL → Codeware (+ Mod Settings, Input Loader).
- [ ] Phase 3: AppearanceMenuMod (AMM).
- [ ] Phase 4: verify CET overlay opens; spawn Jackie via AMM; set follow.
- [ ] Record installed mod versions in SETUP.md table.

## MVP (prove feasibility)
- [x] MVP-0: spawn Jackie in the world — CONFIRMED (companion spawn works; record `Character.Jackie`,
      pinned in config). Idle/proximity schedule mechanism works (time + state correct); just needs coords.
- [x] MVP-1: follows/fights via companion AI — CONFIRMED in-game (follows, fights alongside V, uses
      combat barks). Act-1-independent.
- [~] MVP-2: main-quest decline — UI + decline line built; real detection still stubbed (test toggle).
- [ ] MVP-3: "Jackie returned" persistent flag (not started; schedule currently always-on).

## Immediate future (summon works — these are next up)
- **Talk to Jackie (native interact input + random VO)** — corrected goal: focus on Jackie and press the
  game's *interact key* → he plays a random line (chance + cooldown), pulling from the "conversation" /
  "greetings" pools. Pairs with the tagger "conversation" category (added).
  Reality-check / plan:
    - A *fully native dialogue-choice hub* (like vendors/quest NPCs) is heavy (scene + interaction
      system) → **defer**. Achievable now: a focus+interact trigger — same idea as the "Responsive NPCs"
      / "Talk to Me" mods (reference/reuse), scoped to Jackie + our line pool.
    - **Linchpin = playing his VO on demand.** Two routes:
        - Route A (light): trigger his *existing* in-game VO by id natively — no audio extraction. Prove first.
        - Route B (reliable): play extracted `.wem` clips via **Audioware** (new dependency) — needs the
          sounddb → WolvenKit extract → convert pipeline.
    - **Step 1 = playback proof:** make Jackie say one line on a keypress; that decides Route A vs B.
- Capture coords (noodle / coyote / afterlife) so the schedule actually places idle Jackie at his spots.
- Bike/vehicle arrival for the summon (Jackie rides up + dismounts) — DESIGN §10.1.
- Pin idle Jackie to the exact prop spot (not just "near you") — needs a placement test.
- Real main-quest detection (replace the "Force" test toggle): read tracked quest type / build blocklist.
- ~~Voice pipeline: script `lines.json` from sounddb; extract + convert `.wem → .ogg`.~~ DONE via
  `scrape_jackie.py` (777 lines + `.ogg` from the SoundDB API; no WolvenKit needed).
- Window/overlay hide polish.

## Built this session (mod v0.1 → v0.2)
- `mod/JackieLives/` CET mod: Summon companion, Dismiss, daily schedule (instant spawn by proximity),
  position-capture tool, main-quest decline (test toggle), ImGui control window + hotkeys.
- `deploy.ps1`: one-command deploy to the CET mods folder (auto-detects Steam library).
- `tools/voice-tagger/`: phone-friendly web app to audition + tag voice lines (category/mood/triggers/
  chance/locations/notes), import lines.json / export tags.

## Tier 1 — Framework & functionality
- [ ] Persistent living-NPC presence (start: instant spawn at current scheduled location when V arrives).
- [ ] `JackieCurrentState` schedule state machine (locations + Sleeping/Unavailable).
- [ ] Summon-on-side-job layer (own thin layer over companion AI / Codeware / AMM API).
- [ ] Hard main-quest ban (JournalManager quest-type check + blocklist fallback).
- [ ] "Jackie returned" state flag (persists across saves).
- [ ] Sane mod file structure + dependency list documented.

## Tier 2 — Immersion
- [ ] Retrieval questline (gated on "send Jackie to Vik" choice): rumor → Vik info shard → investigate →
      extraction → settle into the Heywood bar.
- [ ] Vik info shard / message (add, don't rewrite his scene).
- [ ] **Remove mourning content** for Mama Welles, Vik, Misty (targeted scene/quest suppression — NOT just
      a flag; see DESIGN §10.3). Verify whether "Heroes"/ofrenda is gated on body choice.
- [ ] Voice-line system: learn the game's existing bark/scene/VO trigger system; extend it to Jackie's new
      locations/states. Categories: greetings, environmental, combat, idle, emotional, banter, romance.
- [ ] Voice-line cataloguing: pull from sounddb.redmodding.org; tag moments/triggers/mood/probability.
- [ ] **Supporting tool (Claude builds):** phone-friendly local web app to audition + tag voice lines.
- [ ] "Where is Jackie" realistic-movement sub-project: travel time + cool-off between locations; bike
      arrival instead of pop-in. (Most ambitious system — stage last.)
- [ ] Mama Welles' house interior added to an empty Heywood building (advanced; defer within Tier 2).
- [ ] Jackie's bike return (easiest: suppress the gift/package texts; or SMS + inventory handover).
- [ ] Conditional greetings + barks reacting to V's story progress; pour-a-drink interaction.
- [ ] Scarcity behavior: can ignore calls / reply to texts late.
- [ ] **Single-instance enforcement** (Antonia, 2026-06-16): never allow >1 Jackie. v0.7 adds robust
      dismiss + a "Dismiss ALL" cleanup as interim; proper version = summon despawns any existing Jackie
      first, and on mod load/reload reconcile with `AMM.Spawn.spawnedNPCs` so reloads don't orphan one.

## Tier 3 — Details & fun
- [ ] Data-driven dialogue system for the ~1000-message V↔Jackie conversations.
- [ ] Small community-fixer side gigs in Heywood.
- [ ] Custom/AI voice line for V's "not dragging you into this" main-quest decline.
- [ ] Remove Jackie's drink/memory option with the Afterlife bartender.
- [ ] Scattered Jackie mentions in other NPCs (Takemura etc.) — hard, low priority.
- [ ] Romance sub-mod (separate, built on the relationship-sim layer).
- [ ] Polish pass.

## Open decisions
- Retrieval-quest trigger timing (post-Act-1 vs later).
- How aggressively to suppress mourning scenes vs. risk of quest breakage.
- Whether "Heroes"/ofrenda fires regardless of body choice (needs in-game verification).

## Problems & Resolutions (log)
- **"Make Jackie callable by disabling his death flag" (2026-06-16) - REFRAMED, not needed.** Initial idea
  was to flip the "Jackie is dead" fact so a native holocall would connect. Investigated: the native holocall
  (portrait/video) is driven by quest `.scene`/`.questphase` resources and can't be fed custom audio from CET
  Lua; existing mods only convert holocalls->audiocalls or do text-SMS (cyberscript77). The death fact only
  governs how the native contact *renders*, not whether our own dialogue can play. RESOLUTION: build the call
  as our existing voiced choice box ("Calling Jackie..." -> pick up -> callTree) — the death flag is irrelevant
  because we never touch the native phone. A true native holocall stays a separate WolvenKit task.
- **Audioware silent, manifest registered 0 ids (2026-06-16) - RESOLVED.** `Play`/`Duration` did nothing,
  log said "Registry error: not found" and "a total of: 0 id(s)". ROOT CAUSE: the scraped `.ogg` are **Opus**
  codec (header `OpusHead`); Audioware's backend (kira/Symphonia) decodes Ogg-**Vorbis**/WAV/MP3/FLAC, NOT
  Opus, so every entry was rejected. Proven by a stdlib-generated `test_tone.wav` registering + beeping.
  FIX: `tools/convert_audio.py` re-encodes all 777 Opus->Vorbis via a portable ffmpeg (`tools/ffmpeg/`).
  LESSON: ".ogg" is a container; check the CODEC (`head -c 32 file | xxd` -> OpusHead vs vorbis).
- **`goto` is a reserved word in LuaJIT (2026-06-16) - RESOLVED before test.** The branch tree used
  `{ ..., goto = "node" }` and `c.goto`; LuaJIT (CET's runtime) reserves `goto` (Lua 5.2 statement), so this
  would be a SYNTAX ERROR failing the whole mod load. Renamed the field to `to`.
- **Subtitles showed in the blue notification field, not the bottom band (2026-06-16) - FIX deployed.**
  We used `SimpleScreenMessage` -> `UI_Notifications.OnscreenMessage` (objective-style). Real subtitles use
  `UIGameData.ShowDialogLine` (push a `scnDialogLineData`) + `HideDialogLine` - the path Audioware itself
  uses (Codeware.reds/Callback.reds). Switched to it (pcall-guarded, falls back to the old msg).
- **Jackie Lives window always on screen / didn't close with the overlay (2026-06-16).** CET calls
  `onDraw` every frame regardless of overlay state (HUD mods rely on this), so the window was effectively
  always-on. **Resolved (v0.5):** track `onOverlayOpen`/`onOverlayClose` and only draw while the overlay
  is open — the standard pattern AMM uses. Window now appears with the overlay and hides with it.
- **"Jackie record not found" — RESOLVED (2026-06-16).** `AMM.API.GetAMMCharacters()` returns only AMM's
  **19 custom** characters, NOT the base-game roster; Jackie lives in AMM's separate SQLite DB. Fixed by
  discovering his record at runtime from `AMM.Spawn.spawnedNPCs` (v0.3 "Find Jackie" button). Discovered
  record = **`Character.Jackie`**, now pinned in `config.jackieRecord` → summon works with no AMM menu.
- **`Game hour: ?` — RESOLVED (2026-06-16).** `GameTime:GetHour()` returns nil in this version; v0.3's
  multi-method probe finds the working one, so the hour reads correctly (confirmed: hour 4 → "asleep").
- **AMM has no public spawn API.** Its official `AMM.API` (Collabs/API.lua) only exposes appearance +
  character-list functions — no spawn/companion. **Resolution:** reach AMM's internal `Spawn` module via
  `GetMod("AppearanceMenuMod")` and call `Spawn:NewSpawn` → `SpawnNPC` (+ `SetNPCAsCompanion`), using the
  public `API.GetAMMCharacters()` only to look up Jackie's record. Risk: internal API may shift across AMM
  versions — pinned to AMM 2.12.5; revisit if AMM updates.
- **AMM basic spawn is passive (Antonia saw: follows, no combat/voice).** Companion mode + friendly
  attitude is what enables follow/fight/barks. **Resolution:** spawn with companion flag + hedge by
  forcing `SetNPCAsCompanion` and friendly attitude once the puppet handle resolves.
- **Can't test Lua outside the game.** **Resolution:** defensive `pcall` + `[JackieLives]` console
  logging everywhere, so failures are visible and reportable rather than silent crashes.
- **`deploy.ps1` blocked while game running (2026-06-16).** It did `Remove-Item -Recurse` first, which the
  running game/CET blocks (locked folder/handle). **Resolved (v0.6):** switched to `robocopy` overwrite in
  place (no delete) with brief retry — should now work even with the game open; clear error if a file is
  truly locked. Removed the over-promised "Reload all mods" guidance.
- **VO test silent, no errors (2026-06-16).** `AudioEvent/SoundPlayEvent + QueueEvent` and
  `GameObject.PlaySoundEvent` all ran but produced no sound on Jackie. **Fix attempt (v0.6):** use
  `Game.GetAudioSystem():Play(event, entityID, emitter)` (the call working dialogue mods use), plus a
  "play on V" toggle to separate *method-wrong* from *event-not-in-Jackie's-bank* (`ono_v_effort_short`
  is V's grunt). Pending retest + whether SoundDB exposes event ids.
- **deploy.ps1 parse error (2026-06-16).** An em-dash (non-ASCII) in a Write-Host string broke Windows
  PowerShell 5.1's parser (reads file as ANSI). **Resolved:** rewrote the script ASCII-only. Lesson: keep
  .ps1 files pure ASCII.
- **Dismiss Jackie did nothing / multiple Jackies (2026-06-16).** Despawn relied on AMM's `DespawnNPC`
  alone, which silently failed, so dismiss left the NPC in-world; each failed dismiss + new summon stacked
  orphans. **Resolved (v0.7):** robust despawn (AMM -> DynamicEntitySystem `DeleteEntity` -> dispose) +
  a "Dismiss ALL Jackies" cleanup button that sweeps `AMM.Spawn.spawnedNPCs`.
- **Voice recorder caught nothing (2026-06-16) - RESOLVED (v0.10).** ROOT CAUSE: CET `Observe` only fires
  when a *script* calls a function; Jackie's barks are triggered by the game's native C++ code, which never
  goes through the script-side stub of `AudioSystem:Play`, so the hook could never see them (confirmed: 0
  events even unfiltered). FIX: hook the SCRIPTED subtitle controller instead -
  `Observe('SubtitlesGameController','OnHideLine', fn(self,lineData))` - which the game DOES call per
  displayed line (proven by shipping subtitle mods). v0.10 reads `lineData.text/.speakerName/.id`, filters
  to Jackie by speaker, dedupes by String ID, and "Dump to file" writes `recorded_lines.json`. Requires
  subtitles ON. Awaiting Antonia's in-game test.
- **"SoundDB is catalogue-only, audio needs WolvenKit" - WRONG, audio IS downloadable (2026-06-16).** The
  SoundDB frontend plays `.ogg` previews from `https://static.zhincore.eu/cp/vo/<wem>.ogg` (public, returns
  `200 audio/ogg`). Its API (`https://sounddb.zhincore.eu/v1`, OpenAPI at `/api.json`) supports
  `q=actor:Jackie` (777 unique lines; `per_page` caps at 200; `totalCount`=977 counts gender-variant hits).
  `scrape_jackie.py` pages the API + downloads the `.ogg`, killing the WolvenKit-extraction subtask for
  tagging AND making Route-B playback far easier than planned.

## Done
- [x] 2026-06-15 — Kickoff: Option-B design, quiet-life/living-NPC architecture, tier plan, MVP defined.
      Scaffolding (CLAUDE.md, DESIGN.md, TODO.md).
- [x] 2026-06-15 — Confirmed Steam + Patch 2.3/2.31; core mod stack compatible. Chose Vortex. Wrote
      SETUP.md. Folded detail_ideas.txt into DESIGN.md §10 with reality-checks.
- [x] 2026-06-16 — Setup complete (Vortex + stack + AMM; Jackie spawns/follows verified). Built mod v0.1
      (summon companion + schedule + decline + capture), deploy.ps1, and the voice-tagger web app.
- [x] 2026-06-16 — **MVP CONFIRMED in-game (mod v0.3):** Jackie summons, follows, fights alongside V with
      combat barks. Record `Character.Jackie` pinned. Time/schedule state correct (hour 4 = asleep).
      Decline flow built (test toggle). Tagger gained a "conversation" category.
- [~] 2026-06-16 — **v0.4 VO playback experiment** shipped: 3 buttons (AudioEvent / SoundPlayEvent /
      PlaySoundEvent helper) play `Config.talkTest.event` on Jackie. Route A proof. Audioware approved as
      fallback (Route B) if native VO won't play his lines. Awaiting in-game test result.
- [x] 2026-06-16 — **v0.7/v0.8:** fixed deploy.ps1 (ASCII), robust dismiss + "Dismiss ALL" cleanup,
      switched VO to `AudioSystem:Play` (plays on V! method confirmed). Built a **voice recorder** (v0.8)
      that hooks `AudioSystem:Play` and logs the event names firing on Jackie's entity.
      KEY INSIGHT: `AudioSystem:Play` needs **WWise event names** (`eventsmetadata.json`), which are
      DIFFERENT from SoundDB's String IDs / `.wem` paths — that's why his lines weren't findable in the DB.
      Open question: do his scripted dialogue lines even have standalone events (barks/efforts do; deep
      dialogue may need extraction + Audioware = Route B).
- [x] 2026-06-16 — **v0.5: window visibility fixed** (overlay-gated draw). **Talk-to-Jackie trigger built:**
      bindable "Talk to Jackie" key + look-at detection + random line from `Config.talkLines` with
      chance/cooldown (greeting vs conversation pool). Audible result pending the VO route + real event ids.
      Fully native dialogue-choice prompt intentionally deferred (heavy). Awaiting coords from Antonia.
- [x] 2026-06-16 02:36 — **v0.9:** removed unused CET-window buttons (Hide window / Dismiss ALL / Find
      Jackie) per Antonia. Wrote docs/logbook.txt (full chronological history). Session paused for the night.
- [x] 2026-06-16 (day) — **Recorder root-caused & rebuilt (v0.10)** as a subtitle-controller hook
      (`SubtitlesGameController:OnHideLine`) + "Dump to file"; deployed. **Built `scrape_jackie.py`** and
      pulled all 777 Jackie lines + `.ogg` audio from the SoundDB API into the tagger (verified: tagger
      shows 777, audio plays, context/quest hints + metadata preserved). Lifted the tagger waitlist.
- [x] 2026-06-16 (day) — Recorder v0.10 TESTED -> 0 (subtitles were on, lines visible). Recorder SHELVED
      (catalogue already identifies lines). **v0.11: working "Jackie voice" playback** — discovered his ~25
      `ono_jackie_*` + `vo_*jackie*` WWise events in SoundDB; added a dropdown + Play/Random/typed buttons
      and wired the Talk-to-Jackie key to real event pools. **CONFIRMED in-game: `ono_jackie_greet` plays
      on Jackie** (Route A works).
- [x] 2026-06-16 (day) — **v0.12: immersive talk** — look at Jackie + bound key (no overlay) -> weighted
      random grunt: 95% common (greet/curious/phone), 5% rare (bump/additional/laughs_soft). In
      `config.talk` + `config.talkLines`. Deployed.
- [x] 2026-06-16 (day) — **v0.13 ink box FAILED:** `gameuiHUDGameController` is NATIVE in patch 2.3 — it
      has no scriptable `OnInitialize` (CET threw "Function OnInitialize ... does not exist"), and the
      `inkHUDGameController` base is per-MODULE, not the HUD root. So CET Lua can't attach a custom widget
      to the HUD root here. **v0.14:** dropped the ink box; the Talk prompt now uses the game's NATIVE
      on-screen message system (`UI_Notifications.OnscreenMessage` via blackboard — reliable, no attach):
      look at Jackie nearby -> "Talk to Jackie [<key>]" appears -> press key -> grunt. Key label is
      configurable (`config.talk.keyLabel`, default "=" since CET won't bind F). Deployed. **CONFIRMED:
      message prompt shows (blue text) when looking at Jackie; "=" plays the grunt.**
- [ ] **Literal yellow-band dialogue box — still open.** Routes: (a) NIF/World Builder real box at Jackie's
      FIXED spot (needs coords + WolvenKit); (b) a small REDSCRIPT module to hook the native HUD/interaction
      (redscript can wrap native methods Lua can't) — more work, can attempt. CET-Lua alone can't do it in 2.3.
- [x] **CET can't bind F — SOLVED a different way (v0.15, awaiting in-game confirm).** Don't *bind* F;
      *observe* the game's own interact handler. `Observe('PlayerPuppet','OnAction')` is hookable (scripted
      method), so we watch for the Interact/Choice action press and fire Talk-to-Jackie when looking at him.
      No binding, works on moving Jackie, foundation for the real box. `config.talk.logActions` debug toggle
      prints action names to confirm the exact CName if the first test doesn't fire.
- [ ] **Native "talk BOX" at a FIXED spot (Antonia asked 2026-06-16) — deferred, here's why.** The literal
      yellow-band choice box is the native interaction system. Two honest routes, neither a quick CET hack
      (a blind CET-Lua choice-hub push is the same trap that killed v0.13's ink box): (a) **WolvenKit /
      ArchiveXL world-builder** = author a prop+interaction `.archive` placed at world coords — legit but
      GUI-heavy and not smoothly Claude-drivable for a beginner throwaway; (b) **redscript module on Jackie**
      = render a real `gameinteractionsChoiceHubData` from the same module that now catches F (TOP item).
      Recommend (b): one module gives the moving box AND F together. Need to verify the exact 2.3 ChoiceHub
      API before shipping (no blind guess). Captured test coords saved in `config.locations.test`
      (`{-854.737, 1833.329, 36.207}`, yaw 44.4).

## Vehicle arrival (Jackie on his bike)
- [x] 2026-06-17 — **Research done** (`docs/vehicle_arrival_research.md`): verified the spawn
      (DynamicEntitySystem), mount (`AIMountCommand` → `seat_front_left`, AMM recipe), and drive
      (`AIVehicleDriveToPointAutonomousCommand` wrapped in `AINPCCommandEvent`, **queued to the
      VEHICLE not the driver**). Jackie's Arch = `Vehicle.v_sportbike2_arch_jackie_player`.
- [x] 2026-06-17 — **Built `mod/JackieVehicleTest/`** (standalone, like JackieFacialTest/WorkspotTest):
      one button per Antonia's step plan (0 probe → 1 spawn both → 2 mount → 3 spawn-on-bike → 4 drive
      → 5 unmount → 6 spawn-at-distance + drive). BIKE⇄CAR toggle. Deployed to the CET mods folder.
- [ ] **IN-GAME TEST (Antonia):** open CET overlay → "Jackie Vehicle Test" panel → press PROBE,
      paste the [JKVeh] lines to Claude. Then walk steps 1→6 ON A ROAD. Report what each does.
- [ ] **Decision pending on the bike-AI limitation:** vanilla AI does NOT drive motorcycles (no
      mod ever has; Jackie's prologue ride is a hand-authored cutscene). If step 4 fails on the bike
      but a CAR drives (toggle), the pipeline is proven and the bike arrival must be **faked**
      (spawn near/out-of-sight + scripted ride-in/dismount). Don't pre-build either path — wait on
      the test result.

### Problems & Resolutions (vehicle arrival)
- **P:** Vehicle drive commands ignored when sent to the driver puppet's AIControllerComponent.
  **R:** They must be `QueueEvent`'d onto the VEHICLE handle (the puppet channel only takes on-foot
  commands). Mount the driver into `seat_front_left` first or the drive task bails (`IsDriver` check).

- [x] 2026-06-17 — **IN-GAME TEST PASSED.** PROBE all OK. Spawn/mount/spawn-on-bike/drive/unmount
      all work. **The bike DOES drive** (better than the research feared — vanilla-AI bike-riding works
      for Jackie's Arch on this build). Refined per Antonia: bike drove too fast/recklessly. Added a
      **ride-in state machine**: drive at a configurable cruise speed (default 12, button cycles
      8/12/16/22) → at 20 m from V, STOP the bike + Jackie dismounts → sprint → at 10 m downshift to a
      walk → stop ~2 m from V. Step 6 now does the full spawn-at-distance → ride → dismount → walk.
- [ ] **Open: Jackie's Arch livery.** The bike-record cycle (`v_sportbike2_arch_jackie_player` +2
      variants) doesn't show the iconic Arch look Antonia expects. Need to confirm the right record /
      appearance — read the record string shown in the panel and report which index looks correct.
- [ ] **Next:** once the ride-in feel is dialed in, fold a cleaned-up version into JackieLives as a
      "vehicle arrival" option for the holocall summon (alongside the existing walk-in arrival).

- [x] 2026-06-17 — **Test-mod refinements** (per Antonia's 5-test feedback): default cruise speed 8,
      80 m spawn, spawn at a RANDOM ANGLE BEHIND V (rearArrivalPoint), sprint→walk threshold 15 m
      (was 10), stop + become companion at 3 m. Deployed.
- [x] 2026-06-17 — **INTEGRATED vehicle arrival into JackieLives (v0.34).** `Config.call.arriveByVehicle`
      (on) routes the holocall "ask onto a gig" choice to a bike ride-in instead of the walk-in.
      Pipeline (`vehicleArrivalTick`): 6 s after hang-up → spawn bike + Jackie at a random rear point
      80 m out → mount → drive in at speed 8, **re-targeting V's live position every 2 s** → stop +
      dismount at 20 m → sprint to 15 m → walk → companion at 3 m → despawn bike. Reuses
      navmeshArrivalPoint / amm-style mount / sendMoveToPoint / promoteToCompanion. `Config.vehicle`
      holds all tuning. Bike cleaned up in dismiss paths + onShutdown. Deployed.
- [ ] **TEST the integrated call→ride pipeline (Antonia):** Call Jackie (or phone him) → ask him onto
      a gig → hang up → he should ride in on the Arch and walk up. Report feel + any failure.
- [ ] **Known intermittent bug (1/5 tests):** bike + Jackie spawned far apart. Likely the navmesh
      snap pulled Jackie's beside-bike point somewhere else. If it recurs, spawn Jackie AT the bike's
      resolved position post-spawn instead of a pre-computed offset.
- [ ] **Open question:** does AMM `SetNPCAsCompanion` fully adopt a DES-spawned Jackie (combat/follow),
      or only the follow command? Watch the post-arrival companion behaviour and report.

- [x] 2026-06-17 — **Vehicle arrival refinements (v0.34a), call→ride confirmed working.** Per Antonia:
      pre-spawn delay 6.0 → **3.6 s** (40% shorter); **park + dismount at 40 m** (was 20); **walk the
      last 25 m** (sprint→walk threshold 25, was 15); locked the bike to the single normal Arch
      (`v_sportbike2_arch_jackie_player`), no cycling. Added a **STUCK FAILSAFE**: after a 5 s grace
      (climbing on), if the bike crawls < 2 m/s for 2 s he parks early + sprints in on foot (dense
      areas). Mirrored into JackieVehicleTest. Deployed.

- [x] 2026-06-17 — **Fix: vehicle-arrival Jackie now despawns reliably on dismiss (v0.34b).** Root
      cause: he's spawned via the dynamic entity system, so `ammDespawn` deleting via
      `handle:GetEntityID()` could miss -> he'd walk off but never vanish. Now `ammDespawn` deletes by
      the stored `CreateEntity` id (`JL.summon.spawn.id`) first. Walk-away path (role clear + re-issued
      move + 30 s deadline) unchanged. AMM-spawned path unaffected (no `.id`). Deployed.

- [x] 2026-06-17 — **Vehicle arrival polish (v0.35a):** (1) loosened the stuck failsafe (was ditching
      the bike almost always) — now needs < 1 m/s for 4 s after a 7 s grace, and re-issues the drive
      every 3 s (less re-path stutter); (2) pre-spawn wait 3.6 → **1.0 s**; (3) **force re-unmount** —
      one retry ~1.6 s into the sprint + a forced unmount on entering companion range (with a 1 s beat
      before the bike despawns) so he can't get stuck in the mounted pose; (4) **subtitle wipe** — the
      one-off parting line ("Time we were on our way, mamita") now hides after its duration + on
      despawn (it had no auto-hide and stuck forever). Deployed.
