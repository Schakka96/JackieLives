# TODO — Jackie Lives mod

_Update after every major change. See `docs/DESIGN.md` for rationale, `docs/SETUP.md` for install steps._

> 🔀 **This file is JackieLives-only.** The **NCLives** framework (Night City Lives; Jackie = persona #0,
> Evelyn = persona #1) is a **separate repo/project** (`../NCLives/`) — it reuses this engine by porting,
> not by sharing. Keep the two roadmaps/logs apart.

> 📋 **Companion backlog:** `List_of_companion_issues.md` was RESOLVED + MERGED into this file on
> 2026-07-01 (v0.83) and deleted (git history keeps it). Done items: sticky subtitles (v0.80), no-(Leave)
> auto-close (v0.81), fast-travel persistence/respawn (v0.72/v0.79/v0.82). The still-open items live in
> **"📋 Companion backlog (merged 2026-07-01)"** below, next to the START-HERE bug list.

### 🆕 Added 2026-07-09 (v1.47) — picker clears the subtitle line; finale Jackie actually gets placed

⚠️ **UNCOMMITTED on purpose** — the sneak session was live in `init.lua`/`config.lua`, so these edits sit in
the working tree for that session's clean commit. `staging/` deliberately NOT synced for the same reason
(`deploy.ps1` copies from `mod/`, so in-game testing works regardless — but **staging must be re-synced
before any release zip**).

- [x] ✅ **Outfits CONFIRMED WORKING in-game** (Antonia, Misty's). The v1.43 AMM string fix is real.

- [x] 🖥️ **Picker overlapped the native subtitle line.** The v1.42 lower-fifth placement sat right on top of
  it. Box TOP is now pinned at `Config.picker.topFrac` = **36%** of screen height (box occupies 36% → 58%),
  well clear of the subtitle band. `bottomMargin` demoted to a pure safety clamp that never binds at 36%.
  Verified across 720p/1080p/1440p/4K/8K/21:9/32:9 — identical band everywhere, still centred, never off-screen.

- [x] 🐛 **Finale Jackie: "fresh Jackie spawned" in the log, no Jackie in the world, no walk-off, no error.**
  The walk-off was NOT to blame — v1.44 already suppressed it, which is exactly why there was no walk-off
  message. Four real defects, all of them silent:
  * `resolveJackieHandle()` serves two spawn shapes. For a **DES** spawn `sp.id` is an `EntityID`; for an
    **AMM** spawn `sp.id` is the **record string** `"Character.Jackie"`. So its fallback ran
    `Game.FindEntityByID("Character.Jackie")` — meaningless — and the AMM path depended **entirely** on AMM's
    own Cron eventually setting `sp.handle`. AMM sets `spawn.entityID` *synchronously* inside `SpawnNPC`;
    we never looked at it. Now we do, and resolve the body without waiting on AMM.
  * When the handle didn't resolve, the `place` phase **silently fell through to `talk` after 8 s with no log
    at all** — precisely "spawned, but no Jackie, no error". It now logs loudly, **despawns + respawns** (up
    to `finaleSpawnRetries`), and says so if it truly gives up.
  * The finale spawned the same frame V was teleported, at **full black**. AMM drops the body 1 m in front of
    V *at CreateEntity time*, so he could be left at V's **pre-teleport** spot (back at Konpeki) — the same
    not-yet-streamed-world failure class `companionPersistTick` already guards with `startupGrace`. Now it
    waits `finaleSpawnDelay` (0.6 s) for a valid `playerPos()`, then **verifies he landed within
    `finalePlaceTolerance` (6 m) of V** and re-issues the teleport until he has.
  * `catchUpTick` and `companionPersistTick` could **despawn the finale's fresh Jackie** mid-placement and
    respawn their own (which also arms the settle HIDE window over the scene). Both now yield while
    `JL.blazeFinale` is armed.
  * 🐛 **`settleTick` could hide Jackie permanently.** It cleared `hideUntil` even when the handle was nil on
    the reveal frame, skipping `setVisible(h, true)` forever → present, companion, **invisible**. A dead-on
    match for "CET says companion: true but no Jackie around". It now only closes the window once it actually
    reveals him (5 s give-up), and the finale force-clears any settle window and forces `setVisible` +
    `setNpcCollision` on before placing him.
  FSM simulated across: happy path · slow handle · spawned 300 m away · handle never resolves · teleport never
  takes. **Every path now logs**; none falls through silently.
  → **TEST:** run the finale. Expect `finale: fresh Jackie spawned … attempt 1` then
  `finale: Jackie placed N m from V`. If you instead see `handle NEVER RESOLVED -> despawn + respawn` or
  `GAVE UP placing Jackie`, **send Claude those lines** — they distinguish "AMM never gave us a body" from
  "the body existed but was in the wrong place".
  New knobs in `blaze.lua`: `finaleSpawnDelay` / `finaleResolveTimeout` / `finaleSpawnRetries` /
  `finalePlaceTolerance`.

- [x] 🧹 Stray untracked `luac.out` — **mine, and it was junk.** `luac -l -l` (used to disassemble `init.lua`
  and verify `snapToNavmesh` / `blog` / `now` resolve as upvalues rather than nil globals) writes a bytecode
  dump unless you pass `-p`. Deleted, and now gitignored so neither session trips over it again.

### 🆕 Added 2026-07-09 (v1.49) — the finale's `[F] Get in the AV` prompt could never appear

Antonia: *"The [F] button to get into the helicopter does not appear at that coordinate."*

**Root cause — the same shape as the v1.46 stairs bug: a distance check that forgot it has a vertical axis.**
`Blaze.bound.distToPlayer` returns a full **3-D** distance, but `M.yori.roofHeli.radius` was **2.0 m**. That
coordinate (`z = 320.0`) is the roof AV's own origin, which sits *above* the roof deck V walks on — while the
Smasher fight floor (`goro.pos`) is at `z = 308.3`, ~12 m below. So the height difference between V's feet and
the AV's origin could consume the entire 2 m budget on its own, and the prompt could never fire **no matter
where she stood**. Nothing was wrong with `showPrompt` (it's the same helper used elsewhere) or the coordinate.

- [x] 🚁 `roofHeli.radius` 2.0 → **8.0**. Comfortably swallows the vertical offset, and since the roof sits
  ~12 m above the fight floor an 8 m sphere still cannot leak downward and fire during the Smasher fight.
- [x] 📏 **Self-diagnosing.** While in the `escape` stage but out of reach, it now logs the live distances to
  both exits once a second (`[F] prompt NOT shown — … roof AV 3.4 m away (need <= 8.0)`), so if 8.0 is still
  short the radius gets tuned from a real number instead of a second guess.

→ **TEST:** kill Smasher, walk to the roof AV. `[F] Get in the AV` should appear. If it doesn't, read the
`[F] prompt NOT shown` line in `jackie_debug.log` — the smaller distance is what `roofHeli.radius` must exceed.

**Latent, deliberately NOT fixed (needs a decision):** `d1` is measured against `M.yori.heli.pos`
unconditionally, even when no VTOL was ever spawned (`M.cfg.heliRecord` unset). So standing within 5 m of that
empty coordinate would show the prompt for a helicopter that isn't there. It's off the balcony edge so it's
unlikely to bite, but it is real — gate `d1` on the VTOL actually having spawned.

## 🧪 AWAITING WINDOWS IN-GAME TEST — everything shipped 2026-07-09 (v1.41 → v1.46)

Nothing below has been run in-game; it all parse-checks on the Mac and the pure-logic parts are unit-tested.
Test roughly in this order — the cheap, high-information checks first.

1. **Outfits (v1.43) — do this FIRST, it validates the biggest fix.** Visit **Misty's / Afterlife / Redwood**
   (should be collar-down) and **Ginger Panda / Lizzie's** (should be no-jacket). These never worked before.
   If they still look like the noodle-bar Jackie, the fix didn't take.
2. **Bike (v1.41).** In the CET console first: `print(TweakDB:GetFlat("AIGeneralSettings.aiBikeKnockOffModifier"))`
   → expect `1.0`. If it prints `nil` the record was renamed on your patch; the code logs
   `knock-off modifier unreadable -> SKIPPED` and changes nothing. Then cruise through traffic: does he stay on
   the bike? Is `1000.0` right, or does he feel glued? If `Cruise: bike recovered` spams the log, something else
   is wrong.
3. **Look-at (v1.41).** Walk up to Jackie at a venue. Does his head follow you, seated and standing? Grep the log
   for `LookAt: now tracking V (ctor=…)` — **report which ctor won** so the dead branches can be dropped. If you
   see `head tracking OFF`, he just behaves as before (it cannot break him); try `Config.lookAt.bodyPart = "Head"`.
4. **Daily hello (v1.41).** Approach him at a venue → full spoken line. Leave + return the same day → grunt only.
   Sleep to the next day → spoken line again.
5. **Picker (v1.42).** Centred, lower fifth, at your resolution. Watch a **4-option** conversation: the window is
   `NoScrollbar`, so an overflowing list clips silently. `Config.picker.baseH` is the dial.
6. **Blaze finale (v1.44).** Does Jackie appear and stay for the whole conversation? Afterwards, does he still
   *eventually* head home when his companion clock runs out? (That second half proves the suppression gate
   releases rather than sticking on.)
7. **Watson (v1.45).** Cross a bridge after the finale; switch to Quiet Life, save, reload, cross again. If the log
   ever prints `Watson barrier had drifted shut -> re-asserted`, **tell Claude** — it means vanilla actively
   re-locks it and the 5 s cadence may be too slow to stop you walking into a closed bridge.

### 📌 Known-open / deliberately not done (2026-07-09)

- **`Config.stealth` was orphaned at HEAD.** `init.lua` (v1.46 sneak work) reads `Config.stealth` at two sites,
  but the table itself sat uncommitted, so `Config.stealth or {}` silently fell back to `{}` and stealth was
  inert on a fresh clone. Committed alongside this wrap-up. ⚠️ The sneak session is still mid-work on this.
- **`staging/` had drifted** from `mod/` (v1.46 synced neither `init.lua` nor `config.lua`). Re-synced + parse-checked
  all four files. Worth a glance before any release zip: `diff` the two trees.
- ✅ **SETTLED (Antonia, 2026-07-09) — NOT A BUG, DO NOT "FIX".** The companion clock counts **absolute** game
  time, so **sleeping or waiting expires it and sends Jackie home. That is the intended behaviour** ("his shift
  ended"). This is precisely why v1.44's re-arm is scoped to the scripted `blazeSetMidday` jump alone, and why the
  auto-leave suppression is gated on the Blaze scene being live rather than on `JL.mode`. A future session will be
  tempted to switch this to elapsed time — don't.
- **Bike arrival still doesn't set `useKinematic` / `clearTrafficOnPath`.** Both are real, inherited fields, but AMM
  ships the same config for its own bike followers and arrival is confirmed-good in-game — so it was left alone
  rather than regress a working path. Revisit only if arrivals still topple *after* the knock-off fix.
- **`aiBikeKnockOffModifier` is a GLOBAL flat** — while Jackie rides, no NPC biker in the city can be knocked off.
  Ref-counting keeps the window as small as possible, but it isn't zero. Watch traffic during a long cruise.
- 📋 **ANTONIA'S TODO — report the look-at ctor.** The CET marshalling of `entLookAtAddEvent` is unverified (no
  shipped Lua mod constructs one). Walk up to venue Jackie and grep `jackie_debug.log` for
  `LookAt: now tracking V (ctor=…)`. Hand that ctor name to Claude and the two dead branches in
  `jlNewLookAtEvent` get deleted. If it instead logs `head tracking OFF`, he just behaves as he did before
  (it cannot break him) — try `Config.lookAt.bodyPart = "Head"` and report that too.

### 🆕 Added 2026-07-09 (v1.46) — walk-abreast on STAIRS + SLOPES (the jagged teleport in front of V)

Antonia: *"We can't walk up stairs or slopes well because V's elevation changes and so he teleports in a
jagged way in front of V."* Her read was right — the leash had no vertical dimension at all.

**Root cause (two bugs, one symptom).**

1. **The anchor was never grounded.** `abreastTick` built its target as
   `Vector4.new(destX, destY, pp.z, 1.0)` — x/y from a polar offset around V, but **z copied verbatim from
   V**. That is only correct on flat ground. Walking *up* stairs, the point ~5.5 m ahead of V (radius 3.5 +
   leadDistance 2.0) sits **buried inside the steps ahead**; walking *down*, it **floats above them**.
   `AIMoveToCommand` (with `ignoreNavigation = false`) then projects that invalid point onto whatever
   navmesh is nearest — which flips between the **lower and upper floor** from one 0.3 s re-issue to the
   next. Jackie snaps back and forth between the two: the "jagged teleport".
2. **`jlVWalking()` only measures HORIZONTAL speed** (`dx,dy`). On a staircase V's 2-D speed sits right in
   the walk band, so abreast stayed engaged on exactly the geometry it cannot handle.

**Fixes (`init.lua`, `config.lua`):**

- [x] 🪜 **`jlVertical()` — a vertical gate.** Trips on either V's own smoothed `|dz/dt|` (> `slopeRate`,
  0.45 m/s: she's climbing *now*) **or** a standing Jackie-vs-V height gap (> `maxZDelta`, 1.0 m: he's on a
  different step/landing). While it's tripped, abreast stands down and Jackie **trails single-file** —
  which is what you'd actually do on a staircase. `slopeReleaseSeconds` (1.5 s) latches the trail on
  briefly after V levels out, so a mid-staircase landing or a kerb can't flip him back and forth.
  *(A jump also trips it: he trails ~1.5 s, then resumes. Harmless.)*
- [x] 🧭 **The anchor is now snapped down onto the human navmesh** (`snapToNavmesh`, the same helper the
  arrival spawn uses) before it's sent. Built *past* the re-issue throttle, so the navmesh query runs at
  most ~3×/s, not every frame. If the snap fails, or lands further than `maxAnchorZDelta` (2.5 m) from V's
  height — i.e. it found a *different floor*, a balcony or metro deck below — we distrust it and fall back
  to V's z, the old behaviour, which is fine on the flat ground this now runs on. Handles ramps + slopes;
  stairs are handled by the gate above.
- [x] ⚠️ **The handoff hole this would otherwise have opened.** `followKeepCloseTick` (the trail) runs
  **before** `abreastTick` each frame and yields to it — but it yielded on bare `jlVWalking()`, a
  *different* condition from abreast's own gate. Adding a stairs gate to `abreastTick` alone would mean
  that on stairs **the trail stands down AND abreast stands down**, nobody drives Jackie, and he falls back
  to AMM's long native leash. Both ticks now ask **one shared predicate, `jlAbreastOn()`**, so exactly one
  of them owns him at any moment.
- [x] Both new functions are **globals** (`jlVertical`, `jlAbreastOn`) — `init.lua` is at Lua's hard
  200-top-level-`local` limit. Verified: local count unchanged at 186; `luac -p` clean.

→ **TEST:** walk (V's slow walk toggle) up and down a long staircase — e.g. Misty's steps in Little China,
or any megabuilding stairwell — and up a car-ramp/slope. Expected: Jackie drops **behind** you on the
stairs and walks up single-file, then **slides back to your side** ~1.5 s after you reach flat ground. No
snapping, no popping to the far side of the landing.

### 🆕 Added 2026-07-09 (v1.46) — Jackie SHADOWS V when she sneaks (was: walked straight into the enemy)

Antonia: *"currently he crouches right into the enemy who then detects him… definitely disable walk abreast
when sneaking!"*

**Root cause.** Walk-abreast parks Jackie 3.5 m to the side and ~2 m **ahead** of V (`leadDistance`) — exactly
the space she is trying to keep clear while creeping up on a target. And the trail's fallback gait is **`Run`**,
which overshoots a crouch-walking V and leaves him in front of her even once abreast is off.

- [x] 🥷 **`jlVSneaking()`** — reads `Locomotion` from the PlayerStateMachine blackboard. Values resolved **by
  name** via `jlAnimEnum` (`gamePSMLocomotionStates` → `Crouch`, `CrouchSprint`, `CrouchDodge`) and cached,
  never hardcoded. If no name resolves it logs once and reports "not sneaking" — degrading to the old
  behaviour rather than erroring. *(Enum confirmed against `psmImports.script`: Crouch=1, CrouchSprint=11,
  CrouchDodge=12. `Slide=9` is deliberately excluded — a slide is a sprint manoeuvre, not sneaking.)*
- [x] **Abreast is disabled while V crouches** (through the shared `jlAbreastOn()` predicate); the trail takes
  over at `Config.stealth.followDistance` (3 m), behind her, never leading.
- [x] 🐈 **He now actually CROUCHES.** There is no sneak entry in `moveMovementType` (Walk/Run/Sprint only) —
  the crouched gait is the **`alwaysUseStealth` bool** on `AIMoveCommand`, inherited by `AIFollowTargetCommand`.
  Its handler pushes the NPC into the `Stealth` high-level state, and that drives the animation. Set on its own
  `pcall` so a build without the field just ignores it and the follow still works.
- [x] 🔎 **`jlCompanionCheck()` — a one-time diagnostic that should settle the detection bug.** The engine
  hides companions from enemies *for free*: `SenseComponent.ShouldIgnoreIfPlayerCompanion` short-circuits
  sensing, threat-tracking **and** reactions for anyone `AIHumanComponent.IsPlayerCompanion()` accepts — which
  requires his AI role to be `Follower` **and** his `FriendlyTarget` behaviour arg to be the player. AMM's
  companion promotion sets both. So a correctly-promoted Jackie **should already be invisible to guards**, and
  the fact that he wasn't means either (a) the role never stuck, or (b) abreast was simply walking him into
  their faces. We now print which, once, on the first sneak.
- [x] New `Config.stealth` block: `enabled`, `locomotionStates`, `followDistance`, `movement`, `stealthGait`.

→ **TEST:** crouch and creep toward an unaware enemy. Jackie should fall in **behind** you at ~3 m, crouched,
and stay there. Then check `jackie_debug.log` for these two lines:
  * `Stealth: crouch locomotion states resolved -> Crouch=1, CrouchSprint=11, CrouchDodge=12`
    — if instead you see `could NOT resolve any gamePSMLocomotionStates crouch value`, the enum names changed
    and the sneak gate is inert. **Tell Claude.**
  * `Stealth: Jackie IS a Follower-role player companion` — if instead you see
    `⚠ Jackie is NOT registered as a player companion`, **that is the real cause of him being detected**, and
    the takedown work below will not function either until it's fixed. **Tell Claude.**

### ⏳ NEXT (v1.47) — the parallel takedown from The Heist

**Big finding: it is NOT a cutscene, and it IS reusable.** From the extracted
`docs/research/q005_raw/…/q005_06c_playstyles_floor.questphase.json`, Jackie's synchronised takedown is one
parameterised AI command issued to him — no synced-anim pair, no `.scene`, nothing bespoke:

- Params class **`AIFollowerTakedownCommandParams`** → runtime class **`AIFollowerTakedownCommand`**
  (`scripts/core/ai/aiCommand.script`), fields `targetRef : EntityReference`, `target : weak<GameObject>`,
  `approachBeforeTakedown : Bool`, `doNotTeleportIfTargetIsVisible : Bool`.
- **We do not need to build the NodeRef.** `AIFollowerTakedownCommandHandler.Update` (`FollowerTasks.script`)
  checks the runtime `target` handle **first** and only falls back to resolving `targetRef`. So from CET:
  `cmd.target = victimHandle` against any arbitrary NPC, then the usual
  `GetAIControllerComponent():SendCommand(cmd)`.
- The engine owns the animation: the handler sets `CombatTarget`, calls
  `NPCPuppet.ChangeHighLevelState(jackie, Stealth)`, and the **follower behaviour tree's** takedown subtree
  plays the grapple — which is why q005 watches for `BaseStatusEffect.Grappled` on the victim.
- The "synchronisation" with V is **not a feature**: the quest simply waits for V to enter trigger volume
  `#q005_tr_takedown_sync`, then fires the command. We reproduce it by choosing *when* to issue.

**Prerequisite (the whole ballgame):** the takedown task only exists inside the **Follower role's** behaviour
tree. Same prerequisite as the stealth-immunity above — so `jlCompanionCheck()` gates both. AMM's
`Spawn:SetNPCAsCompanion` does `SetAIRole(AIFollowerRole.new())` with `followerRef = #player`, which satisfies it.

**Caveat:** no in-the-wild CET call-site for `AIFollowerTakedownCommand` was found anywhere (GitHub, AMM,
Nexus). The class is RTTI-registered and the send route is native, so it *should* work — but **we would be the
first**, so this needs a real in-game test before it can be trusted.

**Design decided with Antonia (2026-07-09):**
- **Shadow + opportunistic takedown.** Jackie shadows V and, when V takes a target down, fires the follower
  takedown on a *second* enemy in range. He never acts on his own initiative (that would wreck a planned
  approach).
- **Fallback if the command no-ops:** a silent, non-alerting kill with **no animation**. Explicitly *not* a
  faked grapple.

**⚠️ Shipped as an MVP, deliberately manual.** No CET mod anywhere is known to construct
`AIFollowerTakedownCommand`, so it is *unproven from Lua*. Rather than build a 200-line opportunistic
trigger on top of a command that might no-op, v1.47 ships **only the command wrapper and a test button**:

- [x] `jlTakedown(victim)` — builds the command, sets `.target` to the victim handle (never `targetRef`),
  applies `Config.takedown.approachBeforeTakedown` / `.doNotTeleportIfTargetIsVisible`, and sends it via
  `GetAIControllerComponent():SendCommand()`. Refuses early, with a readable reason, when Jackie isn't a
  companion — no Follower role ⇒ no takedown task in his behaviour tree ⇒ the command is silently dropped.
- [x] `jlValidVictim()` — pre-checks the handler's only two target gates, `ScriptedPuppet.IsActive` and
  `not IsBeingGrappled`. Both **fail open**: if a static isn't reachable we let the behaviour tree run its own
  identical validation rather than refuse a good target.
- [x] `jlTakedownLookAt()` + CET button **“TEST: Jackie takedown (look at)”** in the pace-tuner panel.
- [x] `Config.takedown.auto = false` — the opportunistic trigger is NOT built yet, on purpose.

### ✅ v1.48 — why the first takedown attempt did nothing (Antonia: *"the NPC survived"*)

First in-game test: sneaking works; the takedown left the guard standing. **Two independent bugs, both found
in the decompiled scripts.** (For the record — and Antonia asked directly — *nothing in this path ever dealt
damage.* `jlTakedown` only ever built an AI command and handed it to Jackie's controller. There is no kill
code, no "infinite damage", and the silent-kill fallback was designed but never written.)

1. **`combatCommand` was left false.** The game's own takedown order, `PlayerPuppet.OnTakedownOrder`
   (`player.script:3744`), builds *the very same class* and sets `takedownCommand.combatCommand = true` before
   broadcasting it. `AIFollowerCommand.IsCombatCommand()` has **no script callers** — the flag is read
   natively by the follower behaviour tree to route the command into its combat/takedown subtree. Left false,
   the command is accepted and then silently ignored. (Tell: the sibling class `AIFollowerCombatCommand`
   exists for no purpose other than `default combatCommand = true`.)
2. **We were cancelling it ourselves.** `followKeepCloseTick` re-asserts an `AIFollowTargetCommand` every
   1.5 s and `abreastTick` an `AIMoveToCommand` every 0.3 s. A takedown needs several seconds to walk over and
   play the grapple, so our own leash clobbered it mid-approach and walked him back to V.

- [x] `cmd.combatCommand = true` (`Config.takedown.combatCommand`).
- [x] `jlTakedownBusy()` — while a takedown runs, `followKeepCloseTick`, `abreastTick` **and** `catchUpTick`
  all stand down, so nothing re-issues a command over it. This is the one deliberate exception to the v1.46
  handoff invariant: during a takedown *no* tick drives Jackie, because the takedown does.
- [x] `jlTakedownTick()` — watches it to a conclusion and logs which: grapple started / target down / timed
  out after `timeoutSeconds` (15 s), then hands him back to the leash rather than freezing him.
- [x] 🛡️ **Safety guard (Antonia's concern).** `jlValidVictim` now refuses V (`IsPlayer`) and anything not
  `AIA_Hostile` toward V, resolving `EAIAttitude` by name and comparing as ints. These gates **fail closed**
  (an unreadable attitude refuses), unlike the engine's own two gates which fail open. So the look-at button
  cannot order a takedown on V, on Jackie, or on a friendly.

**Delivery note:** the game routes this through `PlayerSquadInterface.BroadcastCommand`, but that only fans
the command out to each squad member via `GiveCommandToSquadMember` → the same `SendCommand` we already call.
Sending straight to Jackie is equivalent and doesn't require him to be in V's combat squad.

→ **RE-TEST (the decisive experiment):** summon Jackie, confirm he's a companion, crouch, aim at an **unaware**
enemy, press *TEST: Jackie takedown (look at)*.
  * **He walks over and grapples the guard** → the mechanism works. Tell Claude, and the automatic
    “V takes one, Jackie takes the other” behaviour gets built on top of this exact call.
  * **Nothing happens, or the panel says the command couldn't be sent** → the class isn't reachable from CET,
    and we fall back to Antonia's chosen option: a silent, non-alerting kill with no animation.
  * Either way, check the `Takedown:` lines in `jackie_debug.log`.

**Then, once proven, the auto-trigger design:** detect “V is taking someone down” by polling nearby enemies
for `BaseStatusEffect.Grappled` — the same signal q005 itself waits on — then pick Jackie's victim from the
unaware hostiles within range of *him* (not of V), excluding V's own victim. The Heist's “synchronisation”
was only ever a trigger volume, so the timing is entirely ours to choose.

### 🧪 Tests

`tools/test_walk_gates.lua` — run `lua tools/test_walk_gates.lua mod/JackieLives/init.lua` from the repo root.
It **extracts the real `jlVWalking` / `jlVertical` / `jlAbreastOn` out of `init.lua`** and runs them against
stubbed game calls, so the tests cannot drift away from the shipped code. 18 assertions, including the handoff
invariant (never zero, never two ticks driving Jackie). Needs no game and no CET — just a stock Lua 5.x.

### 🆕 Added 2026-07-09 (v1.45) — Watson barrier is now HELD open (was a one-shot write)

Antonia asked whether switching Blaze → Quiet Life re-closes Watson ("or else they can't use the bridges").

**Answer: no, and it never did.** The only writes anywhere are `watson_prolog_unlock=1` /
`watson_prolog_lock=0`; nothing sets them back. `jlSetMode` only writes `jl_mode_blaze`, and the v1.44
`Blaze.reset()` touches no facts at all. Verified by grepping every `SetFactStr("watson…")` call site.

**But the unlock was fragile**, so it got hardened anyway:

- [x] 🌉 **The barrier is now self-healing (`jlWatsonApply` / `jlWatsonHoldTick`).** It used to be a single
  write buried in the finale's at-black callback — no read-back, no re-assert. Two ways that loses the
  bridges: the callback never runs (fade path failed), or a later quest tick flips `watson_prolog_lock`
  back. The second is **not hypothetical** — `jlMourningApply` exists precisely because "the quest system
  flips facts back up", and re-asserts every 5 s for exactly that reason.
  Now: opening Watson stamps our own save-persistent marker fact **`jl_watson_open`**, and a 5 s heartbeat
  re-asserts the two barrier facts whenever they drift. All three open-paths (finale, `Blaze.bound.worldUnlock`,
  the CET "TEST: World unlock now" button) route through `jlWatsonApply(true)` so they all stamp the marker.
- [x] **The heartbeat runs in BOTH story modes** and regardless of whether the set-piece is still live —
  deliberately outside the `JL.mode == "blaze"` branch — so switching back to Quiet Life after Blaze cannot
  strand V behind the bridges. With no marker it is an instant no-op, so it **can never open Watson on a
  vanilla playthrough**.
  Logic tested against a fake QuestsSystem: vanilla save untouched · opens once · self-heals after a forced
  re-lock · survives the mode switch · silent when nothing drifted.
  → **TEST:** after the Blaze finale, cross a Watson bridge. Then switch to Quiet Life in settings, save,
  reload, and cross again. `jackie_debug.log` prints `Watson barrier had drifted shut -> re-asserted` if the
  game ever tries to re-lock it — **if you see that line, tell Claude**: it means vanilla is fighting us and
  the 5 s cadence may need tightening.

### 🆕 Added 2026-07-09 (v1.44) — Blaze finale: Jackie no longer walks home before his own scene

Antonia: "Jackie doesn't spawn in the finale scene because he is heading home (max companion time reached
because of CET time to noon!)". Exactly right — **the escape sequence broke its own finale.**

The heist runs at night. The escape calls `blazeSetMidday(12)` so "sunny" reads as actual sunshine. But
Jackie's companion-duration clock (`JL.summon.companionExpiresGame`) is stored in **absolute game seconds**,
so shoving the clock from ~02:00 to 12:00 instantly blows past `maxGameHours` (6 h). The auto-leave fires, he
speaks his parting line and walks off — seconds before the finale needs him. Three fixes:

- [x] **The clock jump no longer counts against his time with V.** `blazeSetMidday` raises
  `JL.rearmCompanionClock`; `onUpdate` re-arms the duration timer on the next tick, once the new time is
  live (it can't call `armCompanionTimer` directly — that's a main-chunk local declared further down the
  file). Checked *before* the expiry test, so the stale deadline can't fire in the same frame. This also
  fixes the overlay's "Set time → midday" button, not just the scripted escape.
- [x] **Auto-leave is suspended for the whole set-piece + finale** (`jlBlazeSceneLive()`), the same way the
  main-quest exit already was. ⚠️ Gated on the scene being **live** (`Blaze.st.active` / armed finale), NOT on
  `JL.mode == "blaze"` — that stays true for the rest of the save, so a mode check would have disabled his
  going-home behaviour *permanently* on a Blaze playthrough.
- [x] **The finale cancels a walk-off already in progress.** If he'd started leaving (e.g. an older save,
  or the clock expired during the fight), `leavingTick` would have kept running and **despawned the fresh
  Jackie the finale spawns** — the conversation would play to an empty spot. The finale's `spawn` phase now
  clears `JL.leaving`, wipes the parting-line subtitle, and drops the stale deadline so the new companion
  re-arms from now instead of inheriting an expired one.
- [x] **The set-piece now actually ends.** `Blaze.reset()` was only ever called when a *new* run started, so
  `Blaze.st.active` stayed true for the rest of the save. The finale calls it on completion: it releases
  `jlBlazeSceneLive()` (handing Jackie back to normal companion rules) and despawns leftover
  Smasher/Takemura/heli entities — including the heli abandoned on the Konpeki roof. `M.autoFired` stays
  set, so the fight cannot re-trigger.

Verified by simulating the 02:00 → 12:00 jump: before, he leaves; after, he stays through the scene, and
normal going-home resumes ~6 h after the finale ends.
→ **TEST:** run the heist to the escape. Does Jackie appear in the finale and stay for the whole
conversation? Afterwards, does he still eventually head home when his companion clock runs out?

### 🆕 Added 2026-07-09 (v1.43) — 🔴 OUTFITS NEVER WORKED. Jackie's appearances now actually apply.

Antonia: "the spawned Jackie in Konpeki Plaza is normal Jackie, not Jackie in suit — check if the names
differ; if not, we're switching his outfits wrong." **The names were right. We were switching them wrong.**
Two independent bugs, both fixed. Full write-up: `docs/research/amm_appearance_research.md`.

- [x] 🔴 **BUG 1 — every appearance we ever asked for was silently ignored.** `ammSpawn` passed AMM's
  `Spawn:NewSpawn(name, id, parameters, ...)` a **table** (`{ app = name }`) where `parameters` must be the
  appearance-name **string**. AMM stores it on `spawn.parameters` and later hands it straight to
  `handle:PrefetchAppearanceChange(x)` / `ScheduleAppearanceChange(x)` — a table where a CName is required
  **silently no-ops**, so Jackie always kept his record default. The trap: AMM's
  `obj.appearanceName = (parameters or {}).app` line reads exactly our `.app` key, so the shape looked
  right — but that field is written once and **never read anywhere in AMM**. Fix: pass the plain string.
  ⚠️ **This was never heist-specific.** The *venue* outfits never applied either — it hid for ~20 versions
  because 3 of the 7 venues ask for `jackie_welles_default`, which is what the silent fallback produced.
  → **TEST:** misty / afterlife / redwood should now be **collar-down**, and ginger / Lizzie's should be
  **no-jacket**. If they still look identical to the noodle bar, the fix didn't take — tell Claude.

- [x] 🔴 **BUG 2 — the companion's outfit wasn't remembered across a respawn.** `catchUpTick` (stranded) and
  `companionPersistTick` (body culled) both call `respawnCompanionAtV()`, which called `ammSpawn(1)` with no
  appearance → back to `Config.defaultAppearance`. So even with Bug 1 fixed, heist Jackie would lose the suit
  the first time Konpeki's streaming culled him — which is constantly. `ammSpawn` now records the RESOLVED
  appearance on `JL.summon.appearance`; `jlCompanionAppearance()` reads it back; `respawnCompanionAtV()`
  captures it before the despawn and brings him back wearing it. (The Blaze finale already respawns him
  explicitly in his normal outfit, so it stays correct.)

- [x] ✅ **Names VERIFIED** against AMM's shipped appearance DB. `Character.Jackie` carries all **17** of his
  appearances — no separate q005 record needed. Quest-tagged names take a **double** underscore
  (`jackie_welles__q005_suit`, `__q000_lizzies_club_no_jacket`); the rest take a single
  (`_default`, `_valentino`, `_wounded`). `jackie_welles_q005_suit` (single) does not exist. All four names
  the mod uses are valid. Also available if the clean suit reads too pristine for a firefight:
  `__q005_suit_dirty` / `_bleeding` / `_wounded`.

**Problems & Resolutions (2026-07-09, outfits):**
1. **A silent no-op is the worst failure mode.** An invalid/wrong-typed appearance produces no error, no log,
   and no visual change — the NPC just keeps what he's wearing. That is why a bug affecting *every* outfit
   in the mod survived ~20 versions. Anywhere we hand a name to the engine, prefer a path that can fail loudly.
2. **`obj.appearanceName = (parameters or {}).app` is a decoy.** It's the only place in AMM that reads an
   `.app` key, it's written and never read, and it made a wrong call shape look researched. Verify against
   the *consumer* of a field, not its assignment.

### 🆕 Added 2026-07-09 (v1.42) — dialogue picker centred + in the lower fifth at any resolution

- [x] 🖥️ **Picker placement (`Config.picker`).** Was a fixed 620x240 px box, centred then nudged **150 px
  left**, at 46% screen height — and the pixel sizes never scaled, so on 4K it read as a small box adrift in
  the upper-left quadrant, and on ultrawides the nudge pulled it off the crosshair. Now everything is
  relative to the display: uniform scale `sh / refH` clamped [0.8, 3.0] (scaled off HEIGHT — width swings
  wildly on 21:9 / 32:9), genuinely centred (`xOffset` knob if it should ever be off-centre), dropped into
  the lower band and bottom-anchored `bottomMargin` above the edge. The name plate + font ride the same
  factor. The box is ~22% of screen height — a shade taller than the 20% band — so the bottom clamp is what
  lands it, which is the point: it can never hang off the bottom at any aspect ratio.
  Placement math verified across 720p/1080p/1440p/4K/8K/21:9/32:9 — every unclamped mode lands at exactly
  75.8%..98.0% of screen height, centred to float error, never off-screen.
  → **TEST:** long 4-option conversations — the window is `NoScrollbar`, so if a tall choice list overflows
  the scaled height it clips silently. `Config.picker.baseH` is the dial.

### 🆕 Added 2026-07-09 (v1.41) — venue polish batch: head-tracking, daily hello, bike anti-crash

Three small immersion items (Antonia). **All three are code-complete + parse-clean on the Mac; ALL await a
Windows in-game test.** `init.lua` was NOT committed this session — the Blaze session was editing it
concurrently (see the Problems log). Staging is NOT synced yet for the same reason.

- [x] 🙂 **Look-at / head tracking at venues (`Config.lookAt`).** A venue Jackie was locked to the yaw his
  seat/waypoint baked in. As a companion he head-tracks V because `sendWalkToPlayer`'s
  `AIFollowTargetCommand` carries `lookAtTarget` — a venue Jackie has no follow command, so nothing ever
  told him to look. Fixed with the engine's own `entLookAtAddEvent`: queued ONCE onto the puppet, after
  which the engine tracks V by itself (no per-frame loop, no yaw math, no jitter). It's an additive
  animation-graph overlay, so it composes with the AMM sit workspot and turns his HEAD, not his body —
  it can't eject him from the barstool. Applies to idle-at-venue Jackie *and* seated-at-dinner Jackie
  (both lack a follow command); the on-foot companion is skipped since he already tracks.
  Arms at 12 m, drops at 15 m (hysteresis), re-arms across a sit/stand. Full write-up +
  the dead ends: `docs/research/lookat_research.md`.
  ⚠️ **The CET-Lua marshalling is UNVERIFIED** (no shipped Lua mod constructs this event). `jlNewLookAtEvent`
  tries all three constructor forms and caches the winner; on total failure it logs once and disables
  tracking — Jackie then behaves exactly as before, so it cannot break him.
  → **TEST:** walk up to Jackie at a venue. Does his head follow you, seated and standing? Check
  `jackie_debug.log` for `LookAt: now tracking V (ctor=…)` and **tell Claude which ctor won** so the dead
  branches can be dropped.

- [x] 👋 **Spoken hello on the first approach of each in-game day (`Config.venueGreet`).** Walking within
  **5 m** of an idle Jackie the first time on a given in-game day now makes him speak a real line (jl_ clip
  + subtitle) instead of only the WWise greet grunt. Later approaches that day fall through to the existing
  grunt bark, so he doesn't recite a full greeting every time you pass his stool. Gender-aware pools; the
  female/male clips of "Don't come here often, do ya? … It's good to see you, chica/cabrón" are the same
  source line, so it reads identically across tracks. All 6 clips verified present in the bank.
  The daily gate uses a **new** `jlGameDay()` (= `floor(total game seconds / 86400)`), NOT `JL.day.count` —
  see the Problems log.
  → **TEST:** approach him at a venue → full spoken hello. Walk away + back the same day → grunt only.
  Sleep to the next day → spoken hello again.

- [x] 🏍️ **Bike anti-crash (`Config.bikePhysics`).** Users report Jackie crashes a lot; the assumed fix was
  "turn his bike's collisions off". **That is impossible AND was the wrong target** — see the Problems log
  and `docs/research/bike_crash_research.md`. Real cause: `HandleBikeCollisionReaction` force-ragdolls an
  NPC off his bike whenever an impact exceeds `KnockOffForce × aiBikeKnockOffModifier`. Shipped:
  (1) raise `AIGeneralSettings.aiBikeKnockOffModifier` to 1000 **only while his Arch exists** (ref-counted
  across the arrival + cruise systems, restored to the *captured original* so a co-installed mod isn't
  clobbered, force-restored in `onShutdown`); (2) god-mode the Arch Invulnerable so a hard hit can't destroy
  it under him; (3) `jlCruiseRightingTick` — if the bike flips or he's thrown anyway (`IsBeingDragged()`
  bypasses the threshold entirely), right it behind V, `PhysicsWakeUp`, re-mount, re-issue the follow.
  → **TEST:** first, in the CET console: `print(TweakDB:GetFlat("AIGeneralSettings.aiBikeKnockOffModifier"))`
  — expect `1.0`. Then cruise with him through traffic. Does he stay on the bike? Is `1000.0` right, or does
  he feel unnaturally glued? Watch for the log line `Cruise: bike recovered` — if it fires constantly,
  something else is wrong.

**Problems & Resolutions (2026-07-09):**
1. **"Disable the bike's collisions" — impossible, and the wrong goal.** The only scriptable collision
   toggle is `PhysicalMeshComponent.ToggleCollision`, on the *visual* branch
   (`entIPlacedComponent → entIVisualComponent → entMeshComponent → entPhysicalMeshComponent`).
   `vehicleChassisComponent` and `entColliderComponent` descend **straight from `entIPlacedComponent`**, so
   it's unreachable — re-verified against the RTTI dump, confirming the older `bike_cruise_research.md` §3.
   The real cause is a dedicated NPC knock-off mechanic. **Notably, that engine code path contains no
   god-mode check**, so the obvious "make the bike invulnerable" fix provably cannot work on its own.
   → Attacked the actual threshold instead.
2. **`JL.day.count` can silently miss a day.** It only advances when `ensureDayTemplate` catches the game
   hour *wrapping* past midnight. A flat 24 h sleep (10:00 → 10:00) never decreases the hour, so the day is
   missed and the "once per day" hello would never re-arm. Verified with a table of sleep scenarios.
   → New `jlGameDay()` derives an absolute day from the monotonic total-seconds clock; it cannot miss.
3. **`useKinematic` on the arrival ride-in is NOT a bug.** It looked like one (cruise sets it, arrival
   doesn't). But AMM ships the identical `useKinematic/useTraffic` config for its own bike followers, and our
   arrival is confirmed-good in-game — so it was left alone rather than regress a working path. Documented as
   a knob to revisit only if arrivals still topple after the knock-off fix.
4. **`init.lua` was contested again.** Mid-session the Blaze session rewrote `blazeFinaleSceneTick` (v1.10,
   "stand him BESIDE V") in the same working tree. Nothing was clobbered this time (my edit failed loudly on
   a stale read instead of overwriting), but per the standing rule `init.lua` was **left uncommitted**.

### 🆕 Added 2026-07-08 (v1.37) — "unavailable" call SOLVED (alive mode) + combat-leash release

**Call fix — RESOLVED in-game (Antonia tested the workbench).** The "temporarily unavailable" card is
ONLY the dead contact (`jackie_dead`); ringing/connecting the alive `jackie` contact shows the see-through
holo with NO card. So:
- [x] **Default `hijackMode = "alive"`** — phone calls now EndCall the dead card, ring the alive avatar,
  connect, and run our branching dialogue.
- [x] **Ringtone for alive mode** — the alive IncomingCall is silent, so we play `Config.call.ringEvent`.
- [x] **Random pickup delay** — rings `alivePickupMin..alivePickupMax` (1.2–3.0 s) before he answers.
- [x] **Early-game disconnected KEPT** — the hijack (and the vanilla-scene silence) only engage once the
  retrieval quest hits the shard-read stage (AWAITING). Before that, V really does get "number
  disconnected" (Jackie believed dead). Gated in `setupCallHijack`.
- [x] **CET ">> Test full ALIVE call (with dialogue)"** button (`jlStartAliveCall`) — runs ring→connect→
  dialogue without the phone (the raw RING/CONNECT buttons only fire one phase, no dialogue).
- [x] **Combat-leash release (v1.35)** — `jlInCombat()`; abreast/keep-close/catch-up yield in combat so
  AMM's native follower combat AI takes over. (Committed 8f0544e.)
- [ ] **TEST (Antonia):** phone Jackie post-shard → alive holo, ringtone, ~1–3 s, then dialogue. And
  confirm early-game (pre-shard) still gives the disconnected card.

### 🔮 FUTURE (Antonia asked) — replace the see-through holo with a CUSTOM image / video

The connected "transparent thingie" is the game's native holocall showing Jackie's live 3D holo-model.
Replacing it (NO full scene rebuild needed for the image case):
- **Custom STATIC image (feasible, ~1 WolvenKit step):** import the picture as a texture (`.xbm` in an
  `.inkatlas`) and ship it in an `.archive` via ArchiveXL — that's the ONLY WolvenKit work, no scene
  editing. Then our Lua/redscript draws it as an `inkImage` overlay on the call window during a call
  (we already draw the dialogue box there, so the same hook adds the image). Moderate effort.
- **Custom VIDEO (harder):** holocalls can play a pre-rendered Bink `.bk2` wired into the call `.scene`
  — needs a `.bk2` encode + WolvenKit scene-graph edit. Bigger lift; only if a still image won't do.
- Decision needed: static image (recommended) vs video, and supply the asset.

### 🆕 Added 2026-07-08 (manual ToDO entry)
Mourning work not done: Mama Welles still calls to tell V about finding something and then sends the bike key as gift.


### 🆕 Added 2026-07-08 (v1.33) — "temporarily unavailable" call fix workbench (NO WolvenKit)

The dialed-Jackie "number temporarily unavailable" card is the **dead contact's holo** (`jackie_dead`).
The hijack fired at `IncomingCall` but let that dead ring play ~2.3 s (+ layered our own ring SFX =
"rings twice"). New **live-switchable hijack** + CET tester so Antonia can find what dodges the card
without WolvenKit. `mod/JackieLives/` (init/config), mirrored to `staging/` + fomod 1.33.
**Awaiting Windows in-game test.**

- [x] `onPlayerCalledJackie` now branches on `Config.nativeCall.hijackMode` (live via `jlCallFix()`):
  - **quick** — short dead ring (`hijackHangupDelay`, default 0.75 s) → EndCall → connect.
  - **instant** — EndCall the dead ring THIS frame, connect in 0.15 s (no ring, no card).
  - **alive** — EndCall the dead card, ring the **alive `jackie`** avatar instead, then connect.
  - **vanilla** — don't hijack (A/B baseline).
- [x] Double-ring fixed: our WWise ring SFX now OFF by default (`hijackOurRingSfx`, toggle in CET).
- [x] `JL.call.activeId` threads the rung contact through `callTick` / open+close window so alive-swap
  ends/connects `jackie`, not `jackie_dead`. Cleared on hang-up.
- [x] CET **"Call fix (temporarily-unavailable experiments)"** header: mode buttons, delay slider,
  ring-SFX toggle, and RAW phase buttons (RING/CONNECT/END × dead/alive) to watch each in isolation.
- [ ] **TEST (Antonia):** set a mode, CALL Jackie from the phone, see which kills the card. Report the
  winner → I bake it into `Config.nativeCall.hijackMode` as the permanent default. (Open Q from the
  probe doc: does ringing/CONNECTing the **alive** `jackie` contact also fire the game's canned Jackie
  call content? The RAW "RING alive / CONNECT alive" buttons answer that directly.)

### 🆕 Added 2026-07-08 (v1.32) — CET declutter, main-mission toggle, no re-entrant call

Batch from Antonia's feedback. `mod/JackieLives/` (init/config/retrieval), mirrored to `staging/` +
fomod bumped to 1.32. **Awaiting Windows in-game test.**

- [x] **Q1 answered (no code needed):** updating the mod does NOT require redoing the recovery quest —
  progress is the per-save game fact `jackielives_stage`, not a mod file. Added a ⚠️ "never rename"
  guard comment in `retrieval.lua` so a future edit can't silently re-lock everyone's saves.
- [x] **Unlock button made findable:** moved the Main-info block (reunion status, AMM/record, game
  time, schedule, companion) to the TOP of the CET window, with an always-visible **"Unlock now — skip
  the quest, Jackie's back"** button right under the status (shown only while still locked).
- [x] **CET declutter:** removed the call-flow test (force AWAITING / call now / force REUNITED), bike
  CRUISE, mouth-flap shuffle slider, v0.84 reunion beats, Misty/Mama shard testers, walk-abreast
  sliders, and companion-spacing / catch-up sliders. Retrieval section reduced to a minimal
  "Reunion quest — dev jumps" collapsing header. Mourning section trimmed to its two real toggles.
- [x] **Native UI toggle (item 3):** Esc → Settings → Jackie Lives → **Gameplay → "Allow Jackie on main
  missions"** (default OFF = Quiet Life; warns it's not recommended). Persisted via `allowMainGigs`;
  short-circuits `isMainQuestActive()` so it also stops him auto-excusing himself mid-main-quest.
- [x] **Re-entrant call fixed:** new `jlCallInProgress()` guards `startCall` + `onPlayerCalledJackie`,
  closing the farewell/hang-up window where a second call could stack over a live one.
- [ ] **STILL OPEN — "number temporarily unavailable" call bug + custom disconnected-phone resource.**
  The mod rings via the native `jackie_dead` holocall contact, which briefly shows the vanilla
  dead/unavailable card before we STOP→CONNECT. Real fix needs a WolvenKit resource override (replace
  the `jackie_dead` / `jackie_holocall.scene` visual) OR switching `Config.nativeCall.id` to `"jackie"`.
  **Needs Windows in-game testing** to confirm which path the "unavailable" text comes from.

### 🆕 Added 2026-07-08 (v1.3) — WALK-ABREAST: aggressive get-into-position

He couldn't catch up to his beside/ahead pocket at V's **walking** pace (eased Run→Walk at 2 m, then
stalled on the drifting anchor). Fix in `abreastTick` (init.lua) + `Config.abreast`, mirrored to
`staging/`. **Awaiting Windows in-game test.**

- [x] Engage after V holds the walk band **2 s** (`walkSustainSeconds` 3.0 → 2.0).
- [x] Catch-up now **Sprints** (`catchUpMovement` Run → Sprint) at a **near-instant heading**
  (`catchUpSmoothSeconds` 0.5) and **commits** until he's within `inPositionDist` (0.8 m) — no early
  ease. Then holds with the tuned Walk + `smoothSeconds` (3.3) averaging.
- [x] All of Antonia's tuned HOLD values (angles, radius, smoothSeconds, side hysteresis) untouched.
- [ ] **TEST (Antonia):** walk (slow toggle) in a straight line and around corners — he should snap
  into the pocket fast, then settle. Tune `catchUpMovement` / `inPositionDist` / `catchUpSmoothSeconds`
  if the sprint-in looks too eager or he overshoots.

### 🆕 Added 2026-07-08 (v1.3) — APPROACH CAMEO: raise Jackie's appearance likelihood

His idle presence was too rare (3-4 of 7 venues run per day). New `approachTick` (init.lua) +
`Config.approach` (config.lua), mirrored to `staging/`. **Awaiting Windows in-game test.**

- [x] When V comes within **20 m** of any of his 7 real venues during **active hours (06:00-00:00)**,
  roll once to **force his schedule to that venue for the rest of the in-game day** (he appears where
  V is). Existing 45 m proximity spawn then places him.
- [x] **35%** first daily appearance; stays 35% on each fresh venue-approach **until one lands**, then
  **10%** the rest of the day (premium spent on a SUCCESS, not a miss — Antonia's call). **Noodle bar
  is always 10%** (V passes it constantly).
- [x] Edge-triggered per venue (must leave + re-enter the 20 m ring to re-roll — no per-tick spam);
  the force only overrides the schedule while V is within 45 m of it (never suppresses his real spot
  when V is elsewhere); resets each in-game day; sleep window left to the secret-nap cameo.
- [ ] **TEST (Antonia):** walk up to a venue where he isn't scheduled → he should sometimes pop in.
  Watch the CET log for `Approach roll: V near <venue> (35%/10%) -> HIT/miss`. Tune the three chances
  in `Config.approach` to taste.

### 🆕 Added 2026-07-08 (v1.3) — dialogue-review pass: gender-gating bug fix + line polish

Antonia's in-game review of the reunion/recovery + companion dialogue (playing **female V**). Fixes
in `config.lua` + `init.lua` (mirrored to `staging/`). **Awaiting Windows in-game test.**

- [x] **ROOT BUG — female V wrongly defaulted to Hermano mode + Jackie said "mano".** `jlDetectGenderOnce()`
      compared `CName` userdata with `==` (`g == CName.new("Female")`), which is unreliable in CET and
      returned false for a female V → locked the mode to **Hermano** and persisted it. **Fix:** read the
      gender as a **string** (`g.value`, with `NameToString`/`tostring` fallbacks) and compare `"Female"`.
      Renamed the persisted guard flag `modeInit` → **`genderLock`** so saves already mis-locked by the
      v1.2 bug **re-detect once** with the fixed read. Logs the raw gender string now, so if it's still
      wrong on Windows Antonia can report what it read. ⚠️ **Can't be tested on Mac (no game).**
- [x] **Ungated Jackie line** in the recovery call `outrage` node said "…scream at me all you want, **mano**"
      hardcoded (no female variant) → even a correct Husbando female V heard "mano". Gated: base "chica",
      `m =` "mano".
- [x] **V "hermano" overuse in the recovery call** — dropped 2 of 3 (kept one: "Relax, hermano…"); the
      `gigs` and `coming` V choices lost the trailing "hermano".
- [x] **Reunion bike line** "…she's right where you left her" (implied V wasn't riding along) → "Drive me
      home? She's your ride, Jackie — here, have your keys back."
- [x] **"Go on then, hermano. Take her for a spin."** → "Let's go, hermano, and you can take her for a spin."
- [x] **Companion small-talk send-off** — dropped the "take care / checkin' in" branch (+ its `care` node);
      only the "let's move" pool remains (per Antonia: only the "let's go" options read right there).
- [x] **"Time we were on our way, mamita"** in Hermano (male-V) mode was a MUTE grunt (text-only override).
      Now maps to a **voiced** male clip "Make moves, mano." (`jl_jackie_vs_vset_jackie_m_1f119a05be52a008`)
      so a male V never hears "mamita" and gets real audio. ⚠️ **VERIFY that clip by ear on Windows.**

### 🆕 v1.31 (2026-07-08) — Misty call suppressed + mourning-text verify TODO

- ✅ **Misty grief call ENABLED** in `JL_MOURNING_FACTS` (`holo_misty_calls_v_start/end_activate`→0).
- ✅ **Mourning-text analysis** (`onscreens.json`): only **2** active-mourning entries (pk=14016 Mama's
  gift text, pk=19159 "say goodbye" message); rest neutral/lore. No override shipped — verify-first.

**⚠️ CHECK-IT-OUT TESTS (Antonia):**
1. **Misty call not over-broad:** with suppress ON, confirm NO unrelated Misty call (Evelyn/tarot) is
   silenced. If one is → re-comment the two `holo_misty_calls_v_*` lines in `JL_MOURNING_FACTS`.
2. **Mourning text:** with suppress ON, check whether Mama's gift message (pk=14016) and pk=19159 still
   arrive. If they DON'T → nothing to do (fact-block already covers it). If they DO → build a full
   `onscreens` localization override (blank those 2 pks) per `docs/mourning_suppression.md`.

---

### 🆕 Added 2026-07-08 — mourning suppression: test results, bug fix, next chunks

**BUILT this session (v0.97–v0.98, pushed):**
- ✅ Mourning fact-suppression framework (`JL_MOURNING_FACTS`): `sq018_active`→0 (ofrenda blocked, gate
  confirmed), `holo_mama_welles_calls_v_*_activate`→0 (Mama grief calls). Preview/Apply/persisted toggle.
- ✅ "Keep El Coyote OPEN" toggle (`JL_BAR_KEEPOPEN`): forces `mama_welles_default_on`,
  `elcoyote_barman_default_on`, `coyote_community_activated`→1.
- ✅ **v0.98 BUGFIX** — calling Jackie no longer triggers the vanilla "number unavailable / 'Jack I got
  no idea where you are'" holocall over our authored call (`jlSilenceVanillaJackieCall` in the hijack hook:
  dis-arms `holo_v_calls_jackie_*` + pulses `holo_interrupt_call`). **Needs in-game test.**

**CONFIRMED from datamining:**
- Vik = `vector` internally; Takemura = `takemura`; Mitch = `mitch` (NOT River — corrected).
- Misty AND Vik world grief are quest-progress-keyed (`q005_active`, `q101_done`, `q005_14_body_at_victors`
  …), NOT a toggle → manual scene edits only (Tier-3).

**⚠️ OPEN TESTS (Antonia, when convenient — not priority):**
1. El Coyote force-open with a **non-Street-Kid** V (Street Kid test showed bar open but **Mama absent** —
   likely lifepath-gated; needs a Corpo/Nomad save to confirm the fact-force actually streams Mama in).
2. With mourning-suppress ON, confirm the **ofrenda/Mama call does NOT fire** when the body was sent to
   **Mama Welles** (the `q005_jackie_to_mama` branch — the case that arms Heroes).
3. Re-test all of the above with a **male V** to verify voice lines.
4. **INVESTIGATE:** after summon+dismiss, at ~10PM El Coyote was **closed**. Likely vanilla day/night bar
   hours OR the community deactivated — determine which (is `keepBarOpen` being overwritten, or is it
   just night hours?).

**NEXT CHUNKS (Claude, one at a time):**
- [ ] `onscreens.json` localization grep → exact "Jackie" line-IDs for Takemura/Mitch/Misty/Vik scene edits.
- [ ] Misty dialogue surgery support (Antonia editing; Claude writes exact node steps once line-IDs known).

---

### 🆕 Added 2026-07-06 — "SAVE JACKIE" alternate-timeline route + mourning removal (design + spike)
Two Antonia asks this session. **Both are a deliberate pivot:** the existing quiet-life mod was built
to NEVER touch the main story (`DESIGN.md` §2); this route DOES. It is a **separate "alternate-timeline"
mode**, not a change to the working layer (which keeps working untouched). Full research +
sources: **`docs/research/main_quest_freeze_research.md`**.

**PART 1 — Remove the mourning (decided: A+B hybrid).** Mama Welles ofrenda, Misty/Vik/V grief lines.
- **A — runtime fact-block the "Heroes" ofrenda quest** in CET (kills the wake set-piece, no WolvenKit).
- **B — WolvenKit scene-node edits** for Vik's clinic + Misty's Esoterica standalone grief lines.
- **Defer** scattered one-off V mentions (Tier 3, per DESIGN §10.3).
- ⚠️ Open decision: blocking Heroes removes its rewards (La Chingona Dorada pistols) — decide how/if V gets them.

**PART 2 — "Save Jackie" route (decided: intercept the death-tail).** Antonia authors the set-piece
(run back in → kill Smasher → roof → kill Takemura → helicopter with a LIVING Jackie → fade → wake at Vik's).
Mod does the state plumbing. **Research verdict:** literal "never complete the Heist + Watson open" is NOT
cleanly achievable (lockdown welded to Heist completion; only savegame precedent) AND gives a sparse
Watson-only world. So per Antonia's own fallback → **let the Heist reach its world-unlock, replace the
cab-death tail with the set-piece, and hold `q101_resurrection` (Johnny/biochip) from ever starting.**
Scripted editing required (once the spike confirms facts):
  1. WolvenKit `.questphase` edit on `q005_heist` — cut/redirect the cab-death tail node.
  2. Decoupled Watson unlock — complete/neutralize the internal "Lockdown" quest / its prevention areas.
  3. Hold `q101_resurrection` from starting (trigger-gate or questphase gate) → no Johnny, no terminal condition.
  4. Journal untrack/park the frozen main quest (`gameJournalManager.UntrackEntry()` + re-track preventer, cf. nexus 6328).
  5. Disable the systemic 2.2 "passenger Johnny" at source (only Johnny surface not gated by q101).
  6. Content hand-off → mod-driven "wake at Vik's" reunion (reuse `reunionMeetTree`/AMM/`completeReunion()`) + NEW Jackie+Vik greeting lines.
  7. Part 1 mourning suppression still applies.

- ✅ **DE-RISK STEP 1 — JLFactDump fact-spike: CONCLUDED 2026-07-06 (verdict: no fact seam).**
  Ran on Antonia's game. v2 added journal-hook + read-poll channels (poll worked; journal hook attached
  but never fired on her build — deprioritised). Poll confirmed `q005_done` and `q101_started` are REAL
  facts and **both already `1` by the No-Tell Motel**, moving as one block tied to the Heist ending.
  **There is no standalone fact that separates "Watson unlocks" from "q101/Johnny starts"** (matches the
  research warning). ⇒ Fact-flipping is the wrong tool. Superseded by the graph read below.
  `mod/JLFactDump/` + `tools/factdiff/factdiff.py` kept in git history (dev tools, not shipped/staged).

- ✅ **DE-RISK STEP 2 — WolvenKit `q005`/`q101` graph read: DONE 2026-07-06. Verdict: FEASIBLE, NO
  graph surgery needed.** Full findings: **`docs/research/q005_graph_findings.md`**. Antonia exported
  the whole q005+q101 quest tree to JSON; Claude traced the fact-setter/condition nodes across all 88
  phases. Key results:
  - **Watson barrier lever = a plain fact: `watson_prolog_unlock=1` (+ `watson_prolog_lock=0`).** Set in
    vanilla inside `q101_j_01_concert` (Love Like Fire — hence the world opening then), and read by NO
    quest condition → consumed by the placed prevention-area system. So the mod can set it directly and
    Watson opens **without q101**.
  - **q005 never installs Johnny/biochip; Jackie even survives the escape in-data**
    (`q005_jackie_follower_escape=1`). Death + biochip-activation are the No-Tell tail → q101. q101 is
    entered only by q005 completing; nothing force-starts it → a Blaze what-if never enters it.
  - **Act-2 content toggles are also plain `_on` facts inside q101** (`apartment_on`,
    `victor_vector_default_on`, `misty_default_on`, `mq033_misty_dialogue_on`,
    `wat_lch_gunsmith_01_default_on`, `radio_on`, `tv_on`, `cyberspace_on`) → replicable from the mod;
    "sparse world" shrinks to "which toggles we choose to set."
  - ⇒ **Supersedes the "graph surgery" plan (Part 2 steps 1-3 above).** The route is mod-side: extend
    the Blaze end (`blaze.lua`) to set `watson_prolog_unlock` etc. + never trigger q101 + wake-at-Vik's.
  - Raw exports (`docs/research/q005_raw/`, `q101_raw/`) are gitignored (CDPR game data, ~25 MB).

- 🔨 **BUILT (awaiting Windows in-game confirm) — Blaze-end Watson-unlock slice.** Added a
  `worldUnlock` helper to `init.lua`'s `Blaze.bind{}` block (sets `watson_prolog_unlock=1` +
  `watson_prolog_lock=0` via `SetFactStr`, idempotent, pcall-guarded) and call it from `blaze.lua`'s
  `cut` stage alongside the fade (the "you make the jump" beat). Pure-Lua module contract kept (blaze.lua
  only calls `M.bound.worldUnlock`; no-ops if unbound). Only runs while `JL.mode=="blaze"` (the tick is
  mode-gated) so Quiet Life is untouched. Both files `luac -p` clean; no new top-level locals (200-cap safe).
  Staging NOT synced + `Config.version` left at 1.0 (WIP; sync on Windows at deploy, per v0.96).
  - `- [ ] CONFIRM (Windows, throwaway save):` quickest test = CET console
    `Game.GetQuestsSystem():SetFactStr("watson_prolog_unlock",1); Game.GetQuestsSystem():SetFactStr("watson_prolog_lock",0)`
    → drive to a Watson boundary: barrier gone? no soft-lock? save/reload clean? Then run the real Blaze
    set-piece to see it fire at the VTOL cut.
  - `- [ ] NEXT slice:` once confirmed, add the Act-2 content toggles to `worldUnlock` (apartment_on,
    victor_vector_default_on, misty_default_on, mq033_misty_dialogue_on, wat_lch_gunsmith_01_default_on,
    radio_on, tv_on, cyberspace_on), one at a time; then wire the wake-at-Vik's scene.

- ✅ **BUILT 2026-07-06 — in-game STORY MODE toggle** (Quiet Life ↔ Blaze of Glory) in the "Jackie Lives"
  menu window (top of `onDraw`). Two buttons + wrapped descriptions; persisted via `JL.mode` +
  `jlSetMode()` (extends `jlSaveSettings`/`jlLoadSettings` for a string setting) and mirrored to the
  **`jl_mode_blaze` quest fact** so a future WolvenKit `q005_heist` questphase edit gates the Heist
  reroute on it. Blaze machinery is WIP — the toggle is the scaffold + the mode selector. 200-local-cap
  safe (field on `JL`, globals only). luajit parse-checked OK. **Decision baked: ONE mod, not two** —
  Blaze `.archive` edits self-gate on the fact, so Quiet Life players get vanilla story. Staging NOT
  synced (Mac session; sync on Windows). `Config.version` left at 1.0 (no deploy).
- 🎬 **BLAZE v1.02 (2026-07-08) — real FADE TO BLACK + finale hardening (init.lua).** Built by the
  fade/finale session; init.lua only (blaze.lua untouched):
  - **Real fade to black → hold → back in** (`startBlazeFade`/`blazeFadeTick`/`drawBlazeFade`, all globals):
    full-screen black ImGui overlay, alpha animated, drawn DURING gameplay (covers the HUD) but **skips the
    pause/ESC/map menus** via `uiInMenu()` so it never blacks those out. `fade()` bind = start the visual;
    `finale()` runs its actions in the fade's **at-full-black** callback so V never sees the teleport.
  - **Finale now:** world-unlock facts → `Retrieval.forceReunion()` (skip shard) → **best-effort mark the
    main quest complete** (succeed + untrack the tracked entry = q005 during the Heist) → teleport V to Vik's.
  - `- [ ] TEST (Windows):` does the screen actually fade to black (not just a caption), stay covered during
    the teleport, and fade back in at Vik's? Does the ESC menu stay visible if opened mid-fade?
  - ▶ **UPCOMING TASKS FOR THE q005-GRAPH SESSION (quest completion — I could only do a cosmetic best-effort):**
    * The finale's "mark complete" only **succeeds + untracks the tracked journal entry** (q005). It is NOT a
      real graph completion, and **q101 isn't started so nothing there is completed**. Provide the **real
      q005 + q101 completion** — the exact completion facts / journal paths from `q005_graph_extract.md` — and
      wire them into the finale (replace/augment the `ChangeEntryState`+`UntrackEntry` best-effort). Verify
      `gameJournalEntryState.Succeeded` / `gameJournalNotifyOption.Notify` enum names are right in-game.
    * Confirm q101 truly never starts after this (the whole point) — or, if the design wants it "completed"
      rather than "never started", decide which and implement accordingly.
- 🎉 **BLAZE OF GLORY — SHIPPABLE (2026-07-09, v1.13). Confirmed in-game end-to-end by Antonia** (lands at the
  finale spot, sunlit/midday, no music, fresh Jackie beside V, holstered/standing/calm, full branching convo).
  Green-lit to publish. See the 2026-07-09 logbook entry for the full batch. **Pre-publish:** deploy
  `r6/tweaks/JackieLives/jl_force_stand.yaml` (fomod covers it); audio logger off by default; mute-on-finale on.
  - ✅ Bosses drop to floor · Takemura removed · scene-Jackie auto-removed by id · dirty-suit fight Jackie ·
    heli line→fade · weather+midday at black · transport-calm (holster/stand/out-of-combat) · fresh-respawn
    Jackie beside V · 1.8s settle · reconciled branching finale convo · Blaze auto-disables quiet-life extras.
  - ✅ **Stuck-scene MUSIC solved as far as CET allows:** the q005 score is fired NATIVELY (proven via 2 audio
    logs) → no Stop() and no scene-abort exist → **MusicVolume=0 mute** is the fix (wired into the finale).
    See [[jackielives-heist-music-native]] + `docs/research/cet_scene_music_teardown.md`.
  - ✅ **BLAZE BRANCH checklist (superseded — kept for history):**
    1. `- [~]` `startFact` = `phonecall_player_with_tbug` falling edge (working in-game; the `spiderbot_glass`
       guess is gone). Fine for ship.
    2. `- [x]` Removed the dead `autoRadius` (v1.05).
    3. `- [ ]` **Real q005/q101 completion** — still the cosmetic best-effort (succeed+untrack). Blaze avoids
       q101 by never completing q005, so this is a polish/nicety, NOT a blocker for ship.
    4. `- [x]` Scene luggage-Jackie auto-removal — done (by persistent id 9001273, v1.07).
    5. `- [ ]` **Real WolvenKit `.journal` objectives** (MVP-B) — still the message-band placeholder. Optional polish.
    6. `- [x]` Fade / subtitles / companion-stays-and-fights — all verified in-game.
    7. `- [x]` Roof-AV escape + bosses fight — verified.
    8. `- [x]` `Blaze.bind` contract complete (holster/stand/weather/mute/scene-Jackie/teardown all bound).
  - **Post-ship polish backlog (optional, non-blocking):** real `.journal` objectives (#5); real q005 graph
    completion (#3); soften the global music-mute (needs a WolvenKit `.scene` edit so the q005 scene actually
    ENDS — only then can music be restored without the bed returning); tuck the CET dev buttons behind a
    "dev tools" collapse for the released overlay.
- 🔨 **BUILT 2026-07-09 (blaze v1.07–v1.08; awaiting Windows in-game test) — immersion batch + finale conversation.**
  `mod/JackieLives/{blaze.lua,init.lua,config.lua}`, mirrored to `staging/`, all three parse-checked.
  - **Jackie fights in the dirty heist suit** — `becomeCompanion(fightAppearance)`; `M.yori.fightAppearance =
    "jackie_welles__q005_suit"`. ⚠️ `q005_suit_dirty` is the *item*; the AMM *appearance* per our docs is
    `jackie_welles__q005_suit` — verify in AMM's list in-game, adjust the field if the suit's wrong.
  - **Takemura removed** (felt weird) — commented out; the fight starts straight on Smasher at the elevator.
    `startYorinobu` sets stage="smasher"; restore instructions are in the code.
  - **Scene luggage-Jackie auto-removed by id** — new `despawnSceneJackie(9001273)` (record Character.Jackie,
    LocKey#47007) fires at fight start, retried ~5 s. Skips our companion (the wrong-handle bug: Dismiss/Go-Home
    target the companion). Overlay also has a "Remove scene Jackie by id" button. `- [ ] VERIFY id is save-stable`.
  - **Heli line → fade** — "Jump!" replaced with `jl_1694284269402939392` ("C'mon, V — let's get outta here");
    the fade now WAITS for that line to finish before firing.
  - **Sunny escape** — when Smasher's down + V reaches the heli, `blazeSetWeather("24h_weather_sunny")` fires
    once. Overlay A/B buttons (Sunny prio3 / Sunny instant / Clear / Reset) + "Set time → midday" (heist is at
    NIGHT, so pair sunny with midday for real sunshine). `- [ ] TEST which combo reads best`.
  - **Spoiler-light CET description** — hints it's intense + the irreversible/disables-main-plot warnings only;
    no fight roster / helicopter / chip-sale / outcome.
  - **FINALE CONVERSATION (item 7) + new destination (item 6):** finale now teleports V to the captured spot
    `{ -1787.921, -450.040, 7.747 }` yaw -1.4 (`M.yori.finalePos`), places the EXISTING companion Jackie next to
    her (~2.2 m ahead, facing her) in his **normal outfit** (best-effort live `ScheduleAppearanceChange`), then
    runs `Config.blazeFinaleTree` — a branching, subtitle-based convo via the existing Branch engine
    (`blazeFinaleSceneTick`). Beats: "we made it" → V asks about the case → Jackie "well…" → V demands the biochip
    → Smasher destroyed it, he's sorry → **V forks: mad (a/b) vs let-it-go (c/d)** → "nobody's ever gonna believe
    it" → Jackie's VOICED "So what now?" (`jl_1812693583769038848`) → V: "Whatever we want, hermano. For once,
    nobody's writing our story but us." Terminal action `blaze_finale_complete` (Jackie stays companion).
  - `- [ ] TEST (throwaway save):` outfit swap actually changes (else respawn approach); Jackie stays put/faces
    V through the convo (follow-tick drift?); choices selectable in blaze mode; long subtitles readable (length-scaled).
- 🔨 **BUILT 2026-07-08 (blaze v1.06; awaiting Windows in-game test) — "ESCAPE THE SCENE" finale teardown (item 10, max-risk).**
  Replaces the guess-y music-stop with the *verified* game calls (from a decompiled-2.x-scripts research
  pass; see the CET-API note). `mod/JackieLives/{blaze.lua,init.lua}`, mirrored to `staging/`, both parse-checked.
  - **Root cause confirmed by datamine:** the heist-gone-wrong music is a **scene/quest music bed**, NOT a
    quest-graph node — there's no fact to flip and **no clean scene-abort API**. And "advance the quest to
    end the scene" is a trap: the only node after the Konpeki escape is `q005_09_no_tell_motel` = the
    death→biochip→q101/Johnny tail Blaze exists to skip. So the fix stays mod-side: tear the scene state
    down without touching the graph.
  - **Finale now runs `blazeFinaleTeardown()` at full black, AFTER the Coyote teleport:**
    1. **`blazeClearCombat()`** — forces V's player-SM Combat slot → OutOfCombat + drops the FT InCombat
       lock + fires the real `LeaveCombat` game tone & `HandleOutOfCombatMix` (kills combat-tension music).
    2. **`blazeStopMusic()`** — `LeaveCombat` tone + out-of-combat mix + best-effort `Stop()` on candidate
       scene-music events (`blazeStopMusic("<event>")` console tester hunts the exact CName → add to
       `BLAZE_MUSIC_STOP`).
    3. **`blazeEndScene()`** — the only script handle on a live `.scene` in 2.x: **fast-forward** it to its
       end (what skip-cutscene uses), auto-deactivated ~6 s later by `blazeSceneFFTick`. Gated on
       `Blaze.cfg.endSceneOnFinale` (default **true**, max-risk).
  - `- [ ] TEST (Antonia, throwaway save):` does the leftover heist music stop at Coyote now? **AND the
    max-risk watch:** does the quest visibly jump forward / does **Johnny start** after the finale? If yes,
    the scene fast-forward cascaded the graph → set `Blaze.cfg.endSceneOnFinale = false` (layers 1–2 still run).
  - **Nuclear reserve (NOT in the auto-finale):** `blazeFastTravelEscape()` console fn triggers a REAL
    fast-travel load (full world teardown = guaranteed music kill) — but only lands at the nearest FT point,
    not Coyote, and needs a valid `pointData` (may need a captured one). Use only if layers 1–3 don't silence
    a stubborn bed; tell me and I'll wire a captured point.
- 🔨 **BUILT 2026-07-08 (blaze v1.05; awaiting Windows in-game test) — Antonia's batch from the checked TODOs.**
  Edits in `mod/JackieLives/{blaze.lua,init.lua}`, mirrored to `staging/`. Both files luajit-parse-checked.
  - **Bosses no longer float:** `M.yori.goro.pos.z` lowered 1 m (309.329 → **308.329**) so the DES-placed
    Takemura/Smasher land ON the elevator floor instead of hovering ~1 m up (both spawn at this spot).
    `- [ ] TEST:` confirm they stand on the ground now; nudge z again if still off.
  - **Finale lands V at El Coyote Cojo, not Vik's** (Antonia's call — was Afterlife, then Coyote). Teleport
    target pulled from `Config.locations.coyote` (`-1262.463, -1002.345, 12.037`, yaw −50.9). Blaze also now
    **forces El Coyote open** (the `JL_BAR_KEEPOPEN` facts) so V doesn't wake in a dead bar.
  - **Jackie's "AV's on the roof" hint bark (item 9):** new `avOnRoof` VO beat = REAL voiced q005 line
    `jl_1783599541039017984` *"Bien pensado. Old man Arasaka's AV should still be parked on the roof."*
    (the line Antonia remembered as "bien pasada"). Fires **once**, in the escape stage (after Smasher's
    down), when V comes within **3 m** (`avHintRadius`) of the elevator spot (`goro.pos`) OR the spawned-VTOL
    spot (`heli.pos`). Points V to the roof AV.
  - **Blaze auto-disables the Quiet-Life extras (Antonia):** while `JL.mode == "blaze"`, the retrieval
    questline tick is **skipped** (no Vik reveal tip, no Badlands shard, no Misty/Mama post-reunion shards),
    and mourning suppression now **always runs** (holds `sq018_active=0` → **ofrenda blocked**, plus the Mama
    + Misty grief holocalls off). Previously mourning only ran in Quiet Life with the toggle on; the
    "Blaze auto-suppresses grief" status line is now actually true.
  - **Heist "gone wrong" music kill (item 10) — BEST-EFFORT, needs Windows capture.** New `blazeStopMusic()`
    global + `stopMusic` bind, called at the finale (at full black). It resets candidate WWise music
    switches and Stops candidate scene-music events — but the **exact event/switch names are guesses**
    (can't verify on Mac). `- [ ] TEST (Antonia):` with the tension music playing, run `blazeStopMusic()` in
    the CET console; if silent → done. If not, run `blazeStopMusic("<name>")` to try specific events and
    tell me the winner → I lock it into `BLAZE_MUSIC_STOP`. (This is the one item that needs an in-game loop.)
- 🔥 **BLAZE v0.99 (2026-07-08) — set-piece now LOADS & runs; 4 fixes + open items.** After the stale-
  deploy fix (require cache-bust `package.loaded["blaze"]=nil` + `M.VERSION` stamp logged on load), the
  fight runs. This session's fixes:
  - **Real subtitles/voice:** `say()` → `speakJackieLine` (real clip + real bottom subtitle band + lip
    flap), not the blue notification band. Still returns clip length for the VO-queue spacing.
  - **Companion no longer walks off:** the main-quest/cutscene "excuse himself" block is skipped when
    `JL.mode == "blaze"` (Blaze intentionally puts Jackie in the Heist to fight).
  - **Auto-start** when V (Blaze + Heist/main-quest tracked) gets within `M.yori.autoRadius` (12 m) of the
    balcony spot; manual "Start fight now (override)" kept.
  - **Scene's 2nd (passive luggage) Jackie:** new "Remove the Jackie I'm looking at" button + `despawnLookAt`
    bind (aim at him; delete → dispose → hide+sink; never touches our companion).
  - **⚠️ HELD / KNOWN-BAD (Antonia, fix NEXT time):** the **12 m proximity gate is a bad trigger** — it can
    spawn Takemura **before the real Yorinobu scene finishes**. Do NOT ship this. Replace with a proper
    trigger: fire only **after** the Yorinobu conversation/scene ends AND the "go to the balcony door"
    objective is actually active — likely a **q005 objective/fact** (ask the q005-extract workstream for the
    id) or a scene-end hook, not a raw distance check. Left as-is for now, logged here.
  - **Other open Blaze items:** auto-remove of the scene Jackie needs his entity id (manual look-at only for
    now); real WolvenKit `.journal` objectives (MVP-B) still pending; fade is still a caption stand-in; full
    q005/interlude/q101 graph completion still delegated to the other workstream. `- [ ] TEST (Windows):`
    confirm subtitles/voice play, companion stays & fights, auto-start timing, scene-Jackie removal.
- 🔨 **BUILT 2026-07-08 (awaiting Windows in-game confirm) — blaze v1.03: elevator spawns, tone-down, roof AV, trimmed overlay.**
  - **Both bosses spawn at ONE elevator spot** (Takemura first; Smasher in the same place after he falls).
    ⚠️ `M.yori.goro.pos` is a PLACEHOLDER (old glass-door capture) — `- [ ] NEED elevator coords from Antonia`.
  - **Boss tone-down:** `hpMul` (Takemura 0.20, Smasher 0.50) via new `weaken` bind (×max Health on spawn).
  - **Start gate = T-Bug phone call ends** — `startFact = "holo_v_calls_tbug_start_done"` (candidate; `- [ ]
    VERIFY via JLFactDump`). Replaces the earlier `spiderbot_glass` guess.
  - **Escape = roof AV** at `-2212.9,1764.67,320` (+2 m). Our spawned VTOL kept in code but dormant unless
    `Blaze.cfg.heliRecord` set via console. Native `[F] Get in the AV` prompt on either.
  - **Overlay trimmed:** removed record grabs / position capture / Start-Reset / config-txt button; added
    **Defeat target (look at)** (force-kill; immortality bypass + test lever) and **Identify target (look at)**
    (logs class/entityID/record/name — use on the luggage-Jackie). `blazeDumpConfig` slimmed to heliRecord.
- 🔨 **BUILT 2026-07-08 (superseded by v1.03 above; awaiting Windows) — blaze v1.01: Shigure-only + fact-gated start + roof escape.**
  - **One weapon now:** dropped the Overture + Kongou spots (you can already grab 2 weapons in the
    penthouse). Only a **Shigure** at the first spot (-2238.37,1761.59,308), radius tightened to 4 m so it
    reads as "find a weapon". `- [ ] VERIFY (Windows):` `Items.Preset_Katana_Shigure` via console.
  - **Fight now gated on a QUEST FACT, not proximity** (kills the KNOWN-BAD 12 m gate). `M.yori.startFact`
    → `M.autoStartTick()` starts the fight when that fact flips = T-Bug opens the penthouse glass doors.
    `getFact` bind added (`GetFactStr`). ⚠️ **`startFact` is a guess (`spiderbot_glass`)** — `- [ ] CAPTURE
    the real fact with JLFactDump in-game AT the door-open beat`, then set it in `M.yori.startFact`.
  - **Objective phases now:** P1 `[ ] Find a weapon / >> Defeat Takemura` → P2 `>> Defeat Adam Smasher`
    → P3 `>> Get to the roof and escape`.
  - **Two escape exits:** our spawned VTOL **and** the AV already on the roof (`M.yori.roofHeli.pos`,
    `- [ ] FILL with Antonia's roof coords` to enable). Within reach of EITHER shows the **NATIVE yellow
    `[F]` interaction prompt "Get in the AV"** (v1.02 — reuses the Talk-to-Jackie `InteractionChoiceHub`
    via new `showPrompt`/`hidePrompt` binds; talk-prompt heartbeat yields while `Blaze.escapePromptActive()`).
    The fade is gated on the **F press** (`Blaze.tryEscapePress` from the OnAction hook), not raw proximity.
  - Existing helicopter kept — V can use either. Fade/finale unchanged (world-unlock + wake at Vik's).
- 🔨 **BUILT 2026-07-08 (superseded by v1.01 above) — blaze v1.00: weapon hand-out + Jackie combat.**
  - **Staged weapon pickups:** `M.yori.weapons` in `blaze.lua` lists 3 weapons, each with a coord +
    50 m radius. `checkWeaponDrops()` (called every `M.tick`, both modes) adds each to V's inventory
    ONCE when V gets within radius. Records: `Items.Preset_Katana_Satori` (katana @ -2238.37,1761.59,308),
    `Items.Preset_Overture` (revolver @ -2227.77,1751.086,308.6), `Items.Preset_Kongou` (Yorinobu's own
    iconic pistol, my pick — normally looted in this very room @ -2203.09,1760.731,307.752). Bind:
    `giveWeapon` in `init.lua` (`Game.AddToInventory`). MVP note: direct inventory-add, NOT a physical
    ground-drop (far more reliable); coords just gate WHEN. `- [ ] VERIFY (Windows):` each record string
    via console `Game.AddToInventory("<rec>",1)` before trusting; swap any that error.
  - **Jackie now fights:** root cause = we set each boss hostile toward V ONLY, so companion Jackie stayed
    a neutral bystander ("Companion: true" but never swings). Fix in `init.lua` `setHostile`: also set the
    boss MUTUALLY hostile with Jackie's companion handle (`JL.summon.spawn.handle`), so his AMM follower
    AI registers the boss as a threat and engages. `- [ ] TEST (Windows):` Jackie attacks Goro/Smasher.
    If still passive, escalate to putting Jackie in the player squad (party/prevention) — noted as next lever.
- ⏸️ **BLAZE OF GLORY — POSTPONED (2026-07-07, Antonia's call).** The experimental Yorinobu set-piece
  below is left in a clean, committed, playable state; no further Blaze work until Antonia resumes it.
  **📌 NOTE FOR THE q005/q101 WORKSTREAM:** the Blaze `finale` deliberately delegates the world-open to
  your **`worldUnlock` fact lever** and does NOT autocomplete any quest graph (force-completing q005 risks
  starting q101 = the Johnny/biochip machinery Blaze exists to skip — see the discussion: fact-flip the
  curated world-state levers + `UntrackEntry`, don't "complete" the quests). Blaze will **eventually
  consume that fuller pulled-fact list** (apartment_on, victor_vector_default_on, misty_default_on, radio/
  tv/cyberspace on, etc.), but **for now you can ignore Blaze entirely** — keep building the fact levers
  for the main-quest-freeze route; Blaze's `finale` will just call into whatever `worldUnlock` ends up doing.
- ⚠️ **BUILT 2026-07-07 (v0.97) — Blaze EXPERIMENTAL "Yorinobu apartment fight" (one-button, WIP, SUSPENDED).**
  Antonia's "leave it here" MVP before pausing Blaze work. New `Blaze.startYorinobu()` + a sequenced
  branch in `M.tick` (`st.mode == "yorinobu"`). One overlay button ("EXPERIMENTAL: Start Yorinobu fight")
  flips to Blaze mode and runs: spawn **Takemura** (hardcoded −2205.531/1767.591/313.370, yaw +45 = NW) +
  objective "Defeat Takemura" → on his defeat (lethal OR non-lethal) spawn **Smasher** (−2226.165/1765.743/
  309.329, yaw −157.5 = SSE) + objective → on his defeat spawn the **heli** (−2191/1752/310, yaw +45 = NW,
  uses the look-at-grabbed `heliRecord`) + objective → V within **5 m** of the heli → **fade** → **finale**.
  Yaw math: game_yaw = −compass_bearing (verified vs the mod's `yawToward`). Jackie **barks** at each beat
  via a new `say()` bind helper + a **VO queue** (clip-length-spaced) using **REAL voiced Jackie clips**
  (Antonia 2026-07-07, `jl_<id>`): Takemura-appear ("Oh shit" → "Estamos bien chingados"), mid-fight
  ("¡Muerte cabrón!"), Takemura-down ("Luckily all clear…"), Smasher-reveal ("Is that Adam Smasher?" →
  "Oh, SHIT!"), Smasher mid-fight ("We ain't dyin' — not today!"), heli ("Jump!"). Two spare clips noted.
  - **Companion-on-Takemura (Antonia's refinement):** the moment Takemura appears, `becomeCompanion` bind
    makes Jackie a **companion** (fights + auto combat barks) and forces the mod **fully active**
    (`Retrieval.forceReunion`). Because `scheduleTick` bails on `JL.summon.active`, this **gates the
    schedule** → no second idle Jackie. Fixes the earlier double-Jackie caveat.
  - **Finale** (new `finale` bind helper): fires the **world-unlock** lever (`watson_prolog_unlock=1`,
    `watson_prolog_lock=0`) → **`Retrieval.forceReunion()`** so the Where's-Jackie **shard is SKIPPED** →
    teleport V to **Vik's** (`Retrieval.Config.vikPos`); companion Jackie **catches up** to Vik's beside
    her (no second spawn). Both files luajit parse-checked. `Config.version` untouched.
  - **HONEST SCOPE:** full **q005/interlude/q101 graph autocompletion** is NOT done here — it's the OTHER
    workstream's job (the `worldUnlock` fact lever + q005/q101 graph research). This finale delivers the
    *playable* result (world opens, wake at Vik's, no Johnny) via the barrier lift + teleport, not a real
    quest-graph completion. The **fade** is still a caption stand-in (no real black-screen), and objectives
    are still the placeholder message band (native `.journal` = MVP-B).
  - `- [ ] TEST (Windows):` stand in Yorinobu's apartment on a throwaway save → grab heli record (look-at)
    → click the experimental button. Watch: do Takemura/Smasher spawn at the right spots/facings & fight?
    Does defeat (non-lethal too) advance? Does the heli appear & the 5 m reach fire? Does the finale land V
    at Vik's with Jackie? **Known caveat:** `forceReunion` unlocks Jackie's schedule, so the schedule MAY
    also spawn a second idle Jackie elsewhere — acceptable for an experimental toy; note if it's ugly.
  - **Questphase note (Antonia's Q):** for THIS manual button we need **no** questphase name — the click is
    the trigger; stand in the apartment. Auto-triggering at the *real* Heist moment would need the q005
    Yorinobu-apartment phase (the other session is extracting q005) — a later, non-MVP step.
- ✅ **BUILT 2026-07-06 (v0.96) — Blaze "kill Smasher & Takemura → escape by VTOL" SET-PIECE (MVP-A).**
  New self-contained module **`blaze.lua`** (global `Blaze`, 200-cap safe, retrieval.lua pattern). Runs
  only while `JL.mode == "blaze"`. State machine: spawn Goro (elevator) + Smasher (balcony, hostile) + a
  hovering AV at 3 captured transforms → poll **Smasher's handle for death** → when dead, unlock "reach
  the VTOL" → V within `reachRadius` (6 m) of the heli → **cut-to-black** (caption stand-in). Reuses the
  proven `spawnDynEntity` DES spawn (bike/Jackie path) for NPCs *and* the heli. init.lua coupling = 4
  one-liners (require, `Blaze.bind{}` in onInit, tick in onUpdate, UI block in onDraw) + 2 globals
  (`discoverBlazeRecord`, `blazeCapture`). Overlay buttons: grab records from AMM's spawned list, capture
  the 3 spots, Start/Reset. Both files luajit parse-checked OK. `Config.version` left at 1.0 (no deploy).
  - **VENUE DECISION baked (fixes the lockdown/blocked-stairs problem):** run it as a STANDALONE what-if
    in the freely-accessible Konpeki suite (not inside the live Heist quest), and stage the escape at the
    apartment **balcony** (heli hovers off the edge) instead of the roof — no roof stairs needed.
  - `- [ ] TEST (Windows):` fill `blaze.lua` M.cfg — grab Smasher/Takemura/AV records via AMM + capture
    the 3 positions; Start; confirm hostiles fight, Smasher-death flips the objective, reaching the heli
    fires the cut. Watch: does the AV hover or fall? (if it drifts, add a per-tick hover-lock re-teleport.)
    Are the DES-spawned bosses actually hostile/combat-active? (may need a combat-stim nudge, not just attitude.)
  - **Objectives are a PLACEHOLDER** (native message band). Real WolvenKit `.journal` objectives = MVP-B,
    hand-authored by Antonia per **`docs/BLAZE_WOLVENKIT_OBJECTIVES.md`**; swap is 2 lines in init.lua's
    `Blaze.bind` (`objective`/`fade` → `JournalManager:ChangeEntryState`). Cut-to-black is also a stand-in
    (real cinematic scene = Tier 3 / WolvenKit).
  - **NEXT — "sell the Relic" chain (design, not yet built):** chip still in Jackie's suitcase → stash at
    Vik's (place a briefcase prop + objective). Then beats, all "go to accessible place → talk/fight":
    (1) **Dex in the Afterlife wants to betray you** — spawn Dex+guards hostile, Jackie fights beside you,
    kill him together (mirrors the canon No-Tell Motel betrayal, pre-empted). (2) **Find a buyer** — best
    lore hook **Evelyn Parker** (she originally tried to cut Dex out); runners-up Mr. Hands / Rogue.
    Optional adds: authenticate the chip at a netrunner (Nix), an Arasaka ambush en route, a buyer's-test
    job, a final double-cross fight, and a sell/destroy/keep choice. No Johnny/illness clock in this
    timeline → it's a clean crime-caper cash-out, all spawn-and-fight (easy). To be written into DESIGN.md.
- ✅ **BUILT 2026-07-06 — mourning suppression worklist:** `docs/mourning_suppression.md` (the A+B edit
  list, owner split, datamining checklist to run alongside the spike, rewards decision flagged).
  `- [ ] BLOCKED:` #1 Heroes fact-block needs the quest ID (datamine on Windows); #3/#4 Vik/Misty scene
  edits need scene paths. Mourning is a Quiet-Life need (Blaze auto-suppresses it).

### 🔊 Added 2026-07-04 — ALL 1200 voice lines now playable (bank rebuilt)
- **`tools/rebuild_bank_yml.py` regenerates the Audioware manifest from the REAL extracted `.Wav`
  files** (no renaming). Antonia ran it on Windows and copied the output to
  the tracked source bank manifest `audioware/JackieLives/JackieLives.yml` (committed) + a `.yml.bak` of the old one (`.bak` gitignored).
- **Why:** Audioware looks each clip up by the exact `file:` name; WolvenKit exports Jackie's VO with the
  game's own stem names (`jackie_q000_f_<hex>.Wav`), but the old manifest referenced `jl_<id>.wav`.
  Mismatch → Audioware drops the WHOLE bank (test_tone Duration = -1, no voice). See memory
  `jackielives-audioware-bank-fix`. The rebuild points the manifest at the real files and references only
  files that exist, so one missing clip can never sink the bank again.
- **The mapping is arithmetic** (no lookup table): a line's String ID = the trailing hex of the wem stem
  in decimal — `int("170a4a14f8405008",16) == 1660220866564214792` → plays as `jl_1660220866564214792`.
  The rebuilt bank emits **two events per file**: `jl_<decimal>` (what `config.lua` uses) **and**
  `jl_<stem>`. So all **2331 keys / 1200 files** are playable, and every `sfx = "jl_<decimal>"` already
  in `config.lua` (47 of them) is verified present in the new bank.
- ⚠️ **ACTION ITEM (do from Windows, where the real `.Wav` live):** the **shipped** manifest
  `staging/r6/audioware/JackieLives/JackieLives.yml` is **still the OLD 1281-key `jl_<id>.wav` version** —
  regenerate it with `rebuild_bank_yml.py` and update `HOW_TO_ADD_JACKIE_VOICES.txt` to the new
  **no-rename** workflow (users just drop the WolvenKit-extracted `.Wav` in — no converting). Until then
  a Nexus download would be silent unless the user's filenames happen to match. (Claude can copy the
  reference YML into staging on request; flagged here so it isn't forgotten.)

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
  - ✅ **TESTED 2026-07-02:** 7a seats him perfectly WITH the walk-to-door + get-in animation. Dismount
    fixed (was "No Jackie handle": seating an AMM-summoned Jackie via look-at left no handle once in the
    driving cam → now we remember the seated handle+vehicle). Added `V.ourSeating` MASTER toggle.
  - 🔎 **LIKELY REDUNDANT — AMM already does this.** Antonia saw a *summoned* Jackie auto-get-in/out of
    cars on his own (the pushed build's 7a/7b are manual-only, so that auto behaviour is pure AMM
    companion logic). → **TEST:** flip "Our seating: OFF" and ride around with a summoned Jackie; if he
    still seats/dismounts, **delete our step-7 code** and just rely on AMM. Known gap either way: his
    **mouth-flaps don't work while seated in the car** (talk-to-him VO — log under bugs).
  - Only if AMM does NOT handle it: port `seatJackieInPlayerCar` into JackieLives (mind 200-locals cap).
- **Jackie body-animation library builder** — new standalone `mod/JackieAnimTest/`. Random/next/replay
  buttons play an AMM `Poses` animation on the looked-at Jackie, print `[JKAnim]` name to console, and
  "Save to library" appends good ones to `jackie_anim_library.txt`. Drives AMM.Poses:GetAllAnimations()
  + PlayAnimationOnTarget (workspot system). `- [ ] TEST:` deploy via
  `.\deploy_probe.ps1 -ModName JackieAnimTest`, confirm anims play + names log + saves land.

### 🟢 START HERE next session (updated 2026-07-02, end of session) — SUCCESSFUL SESSION
**Session 2026-07-02 recap:** the 2026-07-01 bug pile is closed, **walk-abreast landed and tested great**
(now the default companion behaviour), and this build is being **PUBLISHED TO NEXUS** (v0.85b — `staging/`
tree is in lockstep). Only one deferred bug remains open (persist-across-save) plus polish backlog.

**✅ Confirmed working this session:**
- **Walk-abreast (v0.85b)** — Antonia: "amazing," tested in-game. Default ON; closest-side pick; walk-only
  (trails at jog/sprint); tuned defaults baked in. See the v0.85b entry below.

**⏳ Still open (next session picks up here):**
- 🐞 **Persist-across-save** — DEFERRED, disabled (KNOWN BUG #1 below has the full diagnosis + fix ideas).
- ⏳ **Dinner-seated dismiss** (v0.83 fix) — still not verified in-game.
- ▶ **Retire keep-close-follow** (optional, Antonia's call) — fold trail into abreast + comment it out, once
  abreast has proven itself over more play.
- 📋 **Polish backlog** below: sit-coords-don't-persist (blocks the manual seat fixes), venue-interior crash
  gate, dinner walk-off interrupt, Lizzie one-liner, bike-record hunt, main-quest ban / safety-dismount tests.

---
**Bug pile cleared (Antonia tested + confirmed 2026-07-02):**
- ✅ **Jackie walks off on dismiss** (bugs 2b/2e) — CONFIRMED working. The v0.78 `jlRetreatFollow` retreat is good.
- ✅ **Talk-then-dismiss CRASH** — never re-occurred; CONFIRMED solved.
- ✅ **Fast-travel look-at despawn/respawn flicker** (bug 2/2c) — CONFIRMED solved + tested.
- ✅ **Arrival "spawns inside V"** (bug 1 follow-up) — CONFIRMED solved.
- ✅ Earlier confirmed: tutorial popup, both shards, fast-travel catch-up→respawn (2f), mouth flaps (4),
  catch-up teleport (v0.66), dialogue picker (v0.33), respawn pop-in polish (v0.82), dialogue/subtitle polish (v0.80/0.81).

**v0.84 / v0.84b 2026-07-02:**
- 🐞 **Persistence across a load — TESTED, STILL BROKEN → re-DISABLED, deferred.** The v0.84 re-enable
  crashed the save (Jackie pops in V's face frame 1, then crash). Full diagnosis + next ideas in KNOWN BUG
  #1 below. `Config.persist.enabled` is back to `false`; the build is stable.
- ✅ **Walk-abreast — DONE + tuned, now the DEFAULT companion behaviour (v0.85b, 2026-07-02).** Antonia:
  "amazing." Baked-in defaults: `angleRight = 0.85`, `angleLeft = 11.25`, `radius = 3.5`,
  `smoothSeconds = 3.3`, `enabled = true`. Behaviour: smoothed heading (no jitter); **closest-side pick**
  (right vs left, with hysteresis) so he doesn't cut across V; **walk-only** — abreast while V WALKS, normal
  trail when she jogs/sprints (V has 3 speeds, Jackie 2; thresholds `walkMaxSpeed`/`jogMinSpeed`); gentler
  **Run** catch-up (was Sprint), eases to **Walk** to hold. Applies to the companion everywhere, not just
  dinner. CET tuner has right/left/radius/smoothing sliders + a live "V walking/side" readout.
  - ▶ **LONG-TERM (Antonia's call, when ready):** if it keeps feeling great, **retire keep-close-follow** —
    fold any remaining trail need into abreast and comment out `followKeepCloseTick`. Not done yet (trail is
    still the jog/sprint fallback, so keep it for now).

**v0.94 2026-07-04 (reunion subtitle timing + smile variety + quality-of-life):**
- 😀 **Smile variety (which face, not how often).** The catch-his-eye smile always used his own Smile
  (native FacialReaction cat 3, idle 6). New `pickSmileIdle()` + `Config.smile.selfChance`(0.60) /
  `otherIdles`({5}) → when a smile fires it's 60% his own Smile, 40% shared evenly across the "other"
  happy faces (only Joy=5 verified so far). **Overall smile frequency is UNCHANGED** — the `chance`
  roll is untouched; this only picks the expression once a smile has already fired. Extensible: sweep
  cat 3 in JackieLipsync for more happy idles and append to `otherIdles` (they auto-split the 40%).
  - **Smile inventory:** only **2** real happy expressions exist today — Smile(6, his own) + Joy(5).
    The AMM Expressions Overhaul's 36 faces (cat 7, 231–266) are *talking* mouth-shapes for lip-flap,
    NOT smiles. The reunion boost keeps its own even {6,5} rotation (deliberately joyful beat).
- 📖 **Emotional reunion subtitles now scale with LINE LENGTH.** The reunion phone call
  (`reunionCallTree`) + first meeting (`reunionMeetTree`) used a flat fallback hold (3.0 s Jackie / 2.5 s
  V's picks) on the mute build, so long lines flashed by unread. New `readingSecs(text)` +
  `isReunionBeat()` (file-local in the branch-dialogue region, 200-cap safe): `secs = clamp(min, base +
  chars/cps, max)` via `Config.subtitleReading` (`minSecs 2.0`, `base 1.6`, `charsPerSec 22`, `maxSecs
  16`). Anchored so 1–2 words ≈ 2 s, a ~6-word sentence ≈ 3 s (old feel), long lines stretch (~7 s @120
  chars, ~10.7 s @200). Only a **fallback** — a readable voice-clip length still wins, so future voiced
  lines stay lip-synced. Wired into `speakJackieLine` (Jackie) + `Branch.confirm` (V's reply); the same
  value also gates when the choice box opens, so the menu waits until the line's been read. Rest of the
  mod's timing unchanged. Tunable entirely from `Config.subtitleReading`.
- ⏱️ **Main-quest call-refusal notice held too briefly** — doubled `jlDeclineMainQuest`'s on-screen band
  from 4.0 → 8.0 s so the blue "Can't call Jackie during a main mission" notice is readable.
- 🛠️ **CET: "Complete quest now (Jackie is back)" button** added atop the *Retrieval quest* debug panel
  (calls existing `Retrieval.completeReunion()` → REUNITED). Clear label vs the old dev-jargon "Force
  REUNITED (skip, unlock)".
- 🔒 **.gitignore: copyrighted CDPR transcripts** (`audioware/JackieLives/transcripts.json`/`.txt`,
  produced by the voice-tagging session) now excluded like `index.json` — never pushed.
- Version → 0.94; staging synced. *(FOMOD `info.xml` NOT bumped — no release cut this session.)*

**v0.93 2026-07-04 (two bug fixes):**
- 🐛→✅ **Calling Jackie during a MAIN quest failed SILENTLY.** Summon/call during a main quest is a
  deliberate no-op (he won't be dragged into the story), but the only feedback was the CET status text —
  invisible in normal play — so it read as "I did the retrieval quest, why won't he answer?". Fix: one
  new global helper `jlDeclineMainQuest()` now routes EVERY refusal through V's status + log **plus the
  blue on-screen NOTICE band** (`showOnscreenMsg` → `Config.mainQuestBlockNotice`). Wired into all call
  paths: `summonJackie`, `startCall`, `summon_arrival`, the phone-dial hijack `onPlayerCalledJackie`
  (was the fully-silent `return`), and the CET "Test arrival" button. Global (not a top-level `local`) so
  it's callable from `summonJackie` — defined ABOVE `showOnscreenMsg` — and 200-local-cap safe.
- 🐛→✅ **Walk-abreast hijacked STANDING conversation (weird distance, jerky).** `jlVWalking()` treated
  standing still (~0 m/s, which is ≤ `walkMaxSpeed`) as "walking", so abreast held Jackie at a 3.5 m side
  angle that snapped as the camera panned. Fix: abreast is now a NARROW case — it engages only when V is
  in a genuine WALK BAND (faster than new `walkMinSpeed` 0.6 m/s, slower than `jogMinSpeed`, hysteresis on
  both edges) AND has held that band **continuously for `walkSustainSeconds` (3 s)**. When STILL → the
  close 1.5 m trail (`followKeepCloseTick`, `Config.follow.distance`). When jogging/sprinting → same close
  trail. CET tuner now shows live speed + walk-band hold timer. `Config.abreast.walkMinSpeed` /
  `walkSustainSeconds` are live-tunable.
- Version → 0.93; staging + FOMOD `info.xml` synced.

**v0.92 2026-07-04 (small fixes):**
- 🎬 **Cutscene / main-quest → Jackie leaves (and his bike can't spawn).** Instead of gating the cruise
  separately, the existing main-quest walk-off now ALSO fires on a real **cutscene** (`jlInCutscene()` =
  PlayerStateMachine `SceneTier >= 4`; verified no false positives on holocalls/dialogue). Once Jackie
  excuses himself and walks off, the cruise is naturally gated (no companion → no Arch); the cruise gate
  also checks `jlInCutscene()` directly as a belt-and-suspenders. CET debug shows "In cutscene (tier>=4)".
  - v0.92b: the departure is a **bark only** — `startLeaving` uses `speakJackieLine` (VO + subtitle), no
    Branch tree, so **V never replies**. And `updateTalkPrompt` is now gated on `jlInCutscene()` so the
    **dialogue picker / F-prompt can't pop up during a cutscene** (Jackie just barks his bye + walks off).
- 🎙️ **Reunion voice lines = ANOTHER SESSION's job.** Do NOT wire real `sfx` into the reunion trees here.
  Antonia is having a separate session mine the full 1280-line `tools/voice-tagger/lines.json` and pick
  fitting lines for the phone call + first meeting. The reunion trees stay text-only until that lands.
- 🏍️ **Cruise Arch never orphans** — teardown on mod reload/exit + full-dismiss (Follower-Jackster bug class).
- 🧹 **Harden vehicle exclusion** — `getTalkTarget()` (voice path) also skips vehicles, like `lookedAtJackie()`.
- Version -> 0.92; staging synced.

**v0.91 2026-07-04 (small fixes + voice re-activated for the release):**
- 🐛→✅ **"Talk to the bike" bug.** Looking at Jackie's summoned Arch popped the F "Talk to Jackie"
  prompt (and let you converse with the bike). Cause: `lookedAtJackie()`'s record fallback matched any
  entity whose record contains "jackie" — and the Arch is `Vehicle.v_sportbike2_arch_jackie_player`. Fix:
  the fallback now skips anything whose class name contains "vehicle". (init.lua `lookedAtJackie`.)
- 🔊 **Voice re-activated in the STAGING release.** Added `staging/r6/audioware/JackieLives/JackieLives.yml`
  (the Audioware bank manifest) + a `HOW_TO_ADD_JACKIE_VOICES.txt` so the Nexus download is voice-READY.
  Audio files stay OUT (CDPR copyright, gitignored) — users extract them with WolvenKit via Antonia's
  video tutorial. Subtitle-only still works if audio is absent (no crash). Version -> 0.91; staging synced.

**v0.86 BIKE CRUISE folded into JackieLives 2026-07-02 (✅ CONFIRMED GOOD in-game — Antonia 2026-07-06):**
- 🏍️ **Companion Jackie trails V on his Arch when V rides a BIKE.** Proven in JackieVehicleTest (AI
  follow + `useKinematic`), now integrated into the live mod as `Config.cruise` + globals
  `jlCruiseTick/Start/Stop/Follow` (cap-safe; reuse `spawnDynEntity`/`mountAsDriver`/`unmountDriver`/
  `promoteToCompanion`). Flow: settled companion + V mounts a bike → his Arch spawns ~8 m behind → he
  mounts + `AIVehicleFollowCommand(useKinematic, target=player)` → trails V. V dismounts → unmount +
  despawn Arch → back to foot follow. The keep-close/catch-up/abreast ticks are gated on `jlCruise.active`
  so they can't drag him off the bike. **Ghost-trail was NOT shipped** (per Antonia — AI follow only).
  In a CAR, AMM's own companion behaviour seats him as passenger (no code needed).
  → **TEST:** be his companion → hop on a bike → does his Arch spawn + trail you through streets? Dismount
  → does he get off + despawn the bike + resume foot follow? CET debug: "Cruise ON/OFF", "Force start/stop".
  If it misbehaves for the release, set `Config.cruise.enabled = false` (everything else is unaffected).
- ⚠️ **Watch for:** orphaned Arch if teardown misses (cleaned each tick + on dismiss); mount fighting the
  follow role (gated, but verify); heavy traffic snags (kinematic routes around, may clip). Report results.

**v0.85 REUNION RESTRUCTURE 2026-07-02 (✅ CONFIRMED GOOD in-game — Antonia 2026-07-06):**
- 🐛→✅ **BUG FIX: reunion call went to voicemail when Jackie was asleep/busy.** New persisted stage
  **AWAITING_CALL (3)** between SHARD and REUNITED: shard read → Jackie has NO world presence yet (no
  schedule) and **ALWAYS answers** V's call (bypasses the asleep/busy/"disconnected" gates). Reading the
  shard no longer auto-rings — **V must call him**.
- 💬 **New reunion CALL** (`Config.reunionCallTree`, long + emotional, rewritten from Antonia's beats):
  V's outrage he's alive → Jackie asks what V's been up to (V deflects) → "you done hidin'?" → Jackie
  wants back in the city BUT the Relic left a **tracking daemon** 'Saka can follow (→ launches a
  find-a-netrunner/ripper quest; Vik couldn't cut it) → V: we'll fix it, I've got your back → Jackie
  admits no more serious gigs (Mama'd kill him, chuckle) → the nervous **bike** ask (folds in the
  bike-back beat) → ends with "I'm on my way." Emotion cues in (parens).
- 🚶 **Ends with a FOOT walk-in** (reuses the standard foot arrival) → when he reaches V the SHORT
  `Config.reunionMeetTree` plays (teasing they look "used", "take me home") → its end calls
  `Retrieval.completeReunion()` → **REUNITED / full unlock**. Bike is returned + fact `jackielives_daemon`
  set during the walk-in arming.
- Wiring: `startCall`/`onPlayerCalledJackie` allow+always-connect in AWAITING; `callTick` picks
  `reunionCallTree`; new `reunion_arrival`/`reunion_complete` actions; `arrivalGreetTick` plays the meet
  tree; `wasCall`/`withCompanionExtras` know the new trees. Text-only lines (add `sfx` to voice later).
  → **TEST (CET Retrieval debug):** "Force AWAITING" → "Call Jackie now" → does the long reunion call
  play (even if he'd be asleep)? Does he walk in on foot? Does the short first-meeting play + unlock the
  mod? Safety nets: "Force REUNITED (skip)" if the flow snags. Watch `[Retrieval]` / call logs.
- 🆕 **NEW QUEST TO BUILD: remove Jackie's tracking daemon.** The reunion call launches it (sets
  `jackielives_daemon=1`) but it's a **stub** — no objective/quest content yet. Design: V + Jackie seek a
  netrunner/ripperdoc to extract the Relic daemon so he can safely return to the city. Add proper
  quest steps, dialogue, and a resolution. (Ties into why he must "stay out of range" for now.)

**v0.84 immersion pass 2026-07-02 (AWAITING IN-GAME TEST):**
- 🏍️ **"Wants his bike back" reunion beat.** The FIRST holocall after Jackie's back now plays
  `Config.firstCallTree` (relieved greeting → he asks for his Arch → V agrees) instead of the normal
  `callTree`. Agreeing fires the `return_bike` action → `jlReturnJackiesBike()` removes
  `Vehicle.v_sportbike2_arch_jackie_player` from V's garage (`VehicleSystem:EnablePlayerVehicle(rec,false,true)`).
  One-time, persisted via fact `jackielives_bikeback`. Text-only Jackie lines (like seatedTree) — swap in
  real VO later by adding `sfx`. → **TEST:** call Jackie the first time post-reunion → does the bike beat
  play? After hang-up, is Jackie's Arch gone from your garage/vehicle wheel? CET debug: "Give bike back now" /
  "Restore bike (undo)" buttons under the Retrieval header. ⚠️ VERIFY the `EnablePlayerVehicle` 3rd-arg
  behavior + that the Arch is actually the record V owns; tell Claude if the bike doesn't disappear (may
  need a different record or the vanilla "reward" vehicle id).
- 📜 **Misty + Mama Welles shards** (replace mourning convos). Once REUNITED, walking up to Misty's
  Esoterica / El Coyote shows a one-time note: Misty (relief + dark regret he almost died), Mama Welles
  (outraged, overjoyed, "I'll kill him myself if he takes a gig like that again"). In `retrieval.lua`
  `Config.postShards`, proximity-triggered, persisted (`jackielives_shard_misty`/`_mama`). → **TEST:** CET
  debug "Show Misty + Mama shards" / "Reset post-shard flags" under the Retrieval header, or walk up to
  each spot after Jackie's back.
- 🏍️ **STEP 8 bike CRUISE** in `JackieVehicleTest` (Jackie rides his Arch behind V). Research overturned
  the old "AI can't ride bikes" premise: **`AIVehicleFollowCommand` + `useKinematic=true`** is AMM's
  shipping bike-follow (`Scan:SetDriverVehicleToFollow`) — kinematic bikes follow without toppling. Built
  two modes: **AI FOLLOW** (proper; `target = Game.GetPlayer()`, `useTraffic=false`, queued to the bike)
  and **GHOST TRAIL** (per-frame teleport his bike behind V — passes THROUGH traffic). Full write-up:
  `docs/research/bike_cruise_research.md`. ⚠️ **A vehicle hitbox CANNOT be disabled from CET on 2.x**
  (only `PhysicalMeshComponent.ToggleCollision` exists; the chassis collider has no Lua disable) — so the
  requested "disable hitbox" = the ghost-trail workaround. → **TEST:** STEP 3 (Jackie on his Arch) → get
  on your bike → START cruise. AI-follow first: does his Arch trail you through streets? If it snags/won't
  move, flip to GHOST TRAIL. Report which works so we lock one in + port to JackieLives.

**📌 TO ADD / DO (from Antonia 2026-07-02) — not yet built:**
- ⏳ **Mouth-flaps while seated in a car.** Talking to Jackie when he's a passenger doesn't move his
  mouth (VO/lipsync). Investigate whether the in-car workspot/mount state blocks the facial path used
  elsewhere (see `JackieLipsync`); low priority.
- ⏳ **Disable the Mama Welles ofrenda invitation + that whole ofrenda quest.** The base-game "Heroes"
  ofrenda arc (Mama Welles invites V to Jackie's ofrenda, the wake at El Coyote, placing his guns/photo)
  makes no sense once he's alive. Block/short-circuit that quest so it never offers/fires. Needs
  investigation: quest name/phase + how to suppress a base-game quest offer (redscript hook / fact gate /
  quest-node block). Reality-check feasibility before building.
- ⏳ **Disable the mourning conversations with Vik and Misty.** Delete/block the base-game dialogue options
  where V grieves Jackie with Vik and Misty (they contradict him being alive). The Misty/Mama **shards
  above are the replacement content.** Needs: locate those scene/dialogue choices and the cleanest way to
  remove them (block the choice hub / scene, or gate via fact).

**📌 TO ADD / DO (from Antonia 2026-07-03) — 3 new features, feasibility triaged. Recommended build order: #3 → #1 → #2.**

- 📱 **#1 — SCRIPTED TEXT MESSAGING from Jackie.** Pre-written (NOT AI-generated) SMS threads that unlock
  after major quest beats, so Jackie can text V updates. Reference (inspiration only, **do NOT extend it**):
  Immersive Generative Texting (github.com/Hugana/…, 100% redscript) + `docs/research/texting_research.md`
  (written 2026-07-03, has the full API breakdown). **Feasibility: MODERATE — feasible, well-trodden, but
  it's the project's FIRST non-CET-Lua component.** Two real paths (see research note for the full trade):
  - **Path A — runtime injection (recommended).** Push a `gameJournalPhoneMessage` into `JournalManager`
    at runtime, gated on the mod's OWN game facts (`jackielives_*` stage) — the exact fact-gating the mod
    already does. Content stays **data-driven** in a `Config.texts` tree (same shape as the dialogue
    trees). ✅ Fits "unlock after quest developments" perfectly; no quest-graph dependency web.
    ⚠️ **KEY UNKNOWN to spike first:** can we call `JournalManager`/`gameJournalPhoneMessage` from **CET
    Lua** (keeps everything in-stack), or does it require a small **redscript** shim? Answer this before
    committing — it decides whether this is a 1-file Lua add or a new redscript module. Codeware may expose
    enough reflection to do it from Lua.
  - **Path B — authored `.journal` + `.questphase` (WolvenKit/ArchiveXL).** The native "add a message
    thread" wiki route. Static, gated by quest facts. **Intermediate–advanced WolvenKit graph work** →
    heavier for Antonia and pulls in quest-phase editing. Fall back to this only if Path A's API is closed.
  - **Replies?** Decide scope: one-way updates (Jackie texts, V reads) is trivial; branching V-choice
    replies need the choice-hub UI the phone provides (harder). MVP = one-way, add replies later.
  - `- [ ] SPIKE:` prove one hard-coded Jackie text lands in V's phone (Path A from CET first). Then wire
    `Config.texts` + fact gates + the "new message" ping. Watch the init.lua **200-local cap** (globals/module).

- 📟 **#2 — REAL in-game shards (replace the on-screen text popups).** Today the "shards" are `showTip`/
  `tutorialPopup` on-screen cards (`retrieval.lua` `Config.postShards`, `shardLines`), NOT lootable/readable
  Codex shards. Antonia wants actual shard items placed at fixed coords, picked up + read. **Feasibility —
  split into 3, honesty per part:**
  - ✅ **Shard TRACKER tool (EASY, Claude-drivable — do anytime).** A `tools/shard-tracker/` interactive
    tool + a `shards.json` manifest: what shards exist, world coords, whether they display correctly, and
    **last-updated timestamp** per shard. Single source of truth for the text too (generates the strings the
    mod/archive read). Can be a Mac-side CLI/HTML tool OR a CET panel. **This is the concrete deliverable I
    can build now.**
  - ✅ **PLACING — Route 1: CET/Codeware runtime spawn (RECOMMENDED, achieves "place shard X at Y, zero
    WolvenKit").** Reversed my first-pass caution (see `docs/research/shard_placement_research.md`, 2026-07-03).
    The mod already spawns entities at coords + already does proximity→text (`postShards`). Spawn a visible
    shard-case prop at the coord; walk-up shows the note. **"Place shard X at Y" = one row in a Lua table**
    (`{id, pos, title, lines}`) that Claude fully controls — no new files, no tools. Even better: reuse the
    mod's existing position-capture so the loop is **stand at the spot in-game → hotkey → coord saved to the
    shard registry → it spawns there forever.** It's a runtime marker, not a baked Codex shard — fine for
    "walk up and read Jackie's note." Persistence uses the same respawn-on-load machinery Jackie already has.
  - ✅ **PLACING — Route 2: "real" baked shard — CHOSEN (Antonia 2026-07-06).** A proper, readable,
    pick-up-able shard. **Division of labor is locked:** Claude authors ALL text (item record + action
    record = TweakXL YAML, the shard's actual wording = localization JSON, the ArchiveXL `.xl` +
    `.streamingsector` placement from Antonia's captured coords, the tracker). **Antonia does exactly ONE
    WolvenKit action:** create the binary `.journal` onscreen resource (one-time; ~30 s clone per extra
    shard from Claude-supplied values). **Full beginner step-by-step + the Claude/Antonia split are in
    `docs/research/shard_placement_research.md` (see the "✅ DECISION" section at the bottom).** Route 1
    (CET spawn) stays as the zero-WolvenKit fallback if the `.journal` step proves annoying.
    - `- [ ] BUILD (Claude):` shard tracker + `shards.json`, then the TweakXL item/action records +
      localization JSON + a filled-in `.journal` "shard sheet" (the 4 values Antonia pastes).
    - `- [ ] ANTONIA:` capture the shard coord in-game (position-capture hotkey) → send Claude; then do the
      one WolvenKit `.journal` action per the doc.
  - ❌ **NOT worth building:** a tool that cracks open the `.archive` binary and injects files = reimplementing
    WolvenKit's serializer. Route 1 sidesteps this entirely. (Ref: **Missing Persons Read Shard Add-On**,
    Nexus 9018, for the shard-open pattern — study, don't depend.)

- 🎬 **#3 — Jackie reliably LEAVES for cutscenes / near main NPCs / gated off main quests (BUILD FIRST).**
  Most feasible of the three: **pure CET Lua, extends systems that already exist**, no new tools/tech.
  Directly prevents the worst immersion break (Jackie loitering in a scripted Judy/Panam scene). Three parts:
  - **(a) Leave for CUTSCENES.** Detect the cinematic/scene state (gameplay **tier** / `PlayerStateMachine`
    scene-tier, or a scene-lock flag) → auto-dismiss/hide Jackie for the duration, restore after. `- [ ]
    RESEARCH:` which signal cleanly flags "a cutscene/scripted scene is playing" from CET (tier ≥ cinematic).
  - **(b) Leave near DIALOGUE-HEAVY STORY NPCs — say goodbye within ~50 m** (Antonia 2026-07-03). When a
    companion Jackie is out and V approaches a story NPC (Peralezes, Placide, Brigitte, Hellman, Hanako,
    Mitch, Judy, Panam, Goro, River, Kerry, Rogue, PL characters…) within ~50 m, Jackie says a short goodbye
    ("got some biz to attend to, catch you later") and walks off — reuse `startLeaving` + the existing NPC
    enumeration (`getAMMCharacters`/target scan). **Design = ALLOWLIST:** default LEAVE for every story NPC;
    only Vik / Mama Welles / Misty / Delamain (+ in-head Johnny, + Jackie himself) are STAY. **Full character
    list + per-NPC disposition + the record-ID slots live in `docs/story_npc_gate.md`.** `- [ ] RESEARCH:`
    harvest the TweakDB character record IDs from AMM's own database to fill that file's Record ID column.
    Radius tunable (`Config.presence.radius`, default 50 m). Symmetric with the main-quest excuse he already does.
  - **(c) GATE off MAIN quests — extend the existing ban.** `isMainQuestActive()` (reads the tracked journal
    quest type) + `Config.mainQuestExit` + summon-decline ALREADY exist (v0.62, still `- [ ] TEST`-pending —
    see "Main-quest ban" below). Strengthen with Antonia's two ideas: **(i)** an explicit **quest-fact/ID
    blocklist** (belt-and-suspenders for quests the tracked-type check misses), and **(ii)** a **venue/region
    blocklist** (main-quest-exclusive locations) so he won't join even if the journal check lags.
  - ⚠️ **200-local cap:** all of this goes in as **globals or a new module** (e.g. `presence.lua`), never new
    top-level `local`s in init.lua. `- [ ] TEST:` verify he cleanly exits + returns for a real cutscene, a
    Judy encounter, and a main quest — and that he does NOT bail during ordinary free-roam/side jobs.

**📥 Install add (done 2026-07-03):** **Missing Persons — Fixer's Hidden Gems** (Nexus 5058) added to
`docs/SETUP.md` To-Install list per Antonia's request (+ its Read Shard Add-On, 9018, noted for #2).

**Still to test (not yet checked):**
- ⏳ **Dinner-seated dismiss** (v0.83 fix): confirm no "Head home" option while seated + "Enough chillin',
  let's go" ends dinner with no crash.

What's DONE vs what's still open:

**✅ Working now (v0.75):**
- **Tutorial popup FIXED.** All 5 probe variants rendered the same lower-left card, so the culprit was the
  `SignalVariant` call throwing (it made the whole push report failure → blue-band fallback). Baked the
  clean version into `retrieval.lua` `tutorialPopup()` — typed `ToVariant`, **no SignalVariant** (the
  popupManager's DELAYED listener fires on `SetVariant` alone). **Probe fully removed** (`jlPopupProbe` +
  window header gone).
- **Both shard messages written** (`retrieval.lua` Config): Vik's reveal (`tipText`, title "Viktor
  Vektor") + Jackie's Rocky Ridge note (`shardLines`, title "Shard — Jackie Welles"). In-character;
  tweak the prose freely.

**🐞 KNOWN BUGS:**
1. 🐞 **STILL BROKEN (v0.84b, 2026-07-02) — DEFERRED, disabled again. CRASH: companion persistence across a
   load.** The v0.84 world-ready + AMM-ready gate did NOT fix it. On test: **Jackie spawns VISIBLY in V's
   face on the FIRST frame after loading, then the game crashes** — so the respawn fires immediately (grace
   skipped) and the v0.82 settle-hide doesn't catch him. LEADING HYPOTHESIS: on an in-session load `onUpdate`
   keeps running and `playerPos()` never reads nil during the transition, so `worldReadyAt` is a STALE
   pre-load stamp → the 8 s grace "already elapsed" → spawn on frame 1 into a not-streamed world. Re-DISABLED
   (`Config.persist.enabled = false`) so the build stays stable. NEXT FIX IDEAS: (a) reset `worldReadyAt` off
   a real load EVENT (hook a save-load / player `OnGameAttached`) instead of an inferred nil-gap; (b) spawn
   HIDDEN and reveal only once the world is confirmed fully streamed; (c) fall back to a MANUAL "he's back"
   trigger. See `config.lua` `Config.persist` + init.lua `companionPersistTick`/`respawnCompanionAtV`.
2. ✅ **SOLVED + TESTED (2026-07-02). Jackie despawns/respawns when V LOOKS AT him after a fast-travel.**
   Confirmed fixed in-game by Antonia. (Left below for history / in case it regresses.)
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
- [x] **Seat tuner didn't move him + coords didn't persist (old S4). — FIXED v1.1 (2026-07-08, awaiting
      in-game test.)** TWO bugs, both fixed:
      **(A) "Slides but he's solid as a rock" — the re-seat never moved him.** Root cause: the re-seat
      **teleported** him (`placeAtExact` → `AITeleportCommand`) then replayed the sit. But a puppet locked in
      an AMM sit-workspot **rejects that teleport** — `StopInDevice` starts releasing him, but the instant
      teleport is eaten while he's still pinned to the pose, so he never moves and the re-sit re-pins him at
      the OLD spot. (Proof it wasn't collision — idle Jackie's collision is already OFF via
      `Config.idleNoCollision=true`; and idle WANDER gets him up fine because it drives him with a *walk*
      command, which the AI accepts, not a teleport, which it doesn't. v0.45's deferred-timing patch never
      truly fixed this.) Fix: **`tunerApply` now DESPAWN + RESPAWNS him onto the tuned seat** instead of
      teleporting. A freshly-spawned puppet is standing/unpinned, so the normal placement path
      (`wanderTick` → `applyIdlePose`) seats him exactly where we point it, every time. `wanderTick` gained
      `JL.idle.forceStartIdx` (place him on THIS seat, not a random waypoint) + a long hold-dwell so he
      doesn't wander off mid-tune. Live-slide still works (debounced to 0.5 s, self-throttles while a respawn
      is in flight); he **blinks** out/in each re-seat — accepted as fine for a dev tuner.
      **(A2) "pick the venue, then walk over" even while staring at him.** `tunerHere()` needs
      `JL.idle.locationKey == JL.tuner.key`, but the tuner key defaulted to `noodle`, so tuning Jackie where
      the SCHEDULE put him (e.g. Afterlife) silently no-op'd every slider + the re-seat button. Fix: the tuner
      now **auto-points at the venue where idle Jackie actually is** (adopts `JL.idle.locationKey` when he's
      settled at a sit-capable venue, unless he's still walking to a force-picked venue). Just walk up to him.
      **(B) Coords didn't survive a reload.** The tuner only live-patched in-memory `Config`; on reload
      config.lua was re-`require`d with its OLD baked coords. Fix: **"Save seat (survives reload)"** button
      write-backs each committed seat to `jl_seats.txt` (`key|sitSeatIdx|x|y|z|yaw`); `onInit` →
      `jlLoadSeats()` re-applies every override into the live `Config` waypoint. New globals
      (200-locals-cap-safe): `jlApplySeatOverride`/`jlSaveSeats`/`jlPersistSeat`/`jlLoadSeats` +
      `JL.idle.forceStartIdx`. **TEST:** (1) tune a seat → he re-seats (blinks) at the new spot each nudge;
      (2) Save → reload the save → he sits at the tuned spot, not the old one. (Unblocks the manual
      sitting-position fix above.)
- [ ] **Venue interiors break the game (old S3), e.g. Lizzie's.** He tries to path INTO an interior and it
      breaks. Keep every dinner seat at an exterior-reachable spot that never triggers an interior load; gate
      any must-be-interior venue out of the picker until proven stable.

**🍽️ Dinner outing polish (old S3):**
- [x] **Walk abreast, not trailing.** DONE + tuned + ON by default for the companion everywhere (v0.85b,
      2026-07-02) — not just the dinner walk. Closest-side pick, smoothed heading, walk-only (trails at
      jog/sprint). Defaults baked into `Config.abreast`. See the v0.85b entry in the START-HERE section.

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
- [x] **Companion catch-up teleport (v0.66).** CONFIRMED working (2026-07-02) — landing beside V, and the
      culled-entity case is now covered by the v0.79 respawn + v0.84 persist.
- [x] **Bug 1 follow-up — "spawns inside V" on a FAILED approach.** CONFIRMED solved (2026-07-02) — arrival
      fallbacks now place him beside V, not on her.
- [ ] (prior v0.65 tasks below — all DEPLOYED in v0.65, awaiting in-game test)
- [x] **Bike record — ✅ RESOLVED (confirmed in-game after v0.85).** Jackie's real (gold) Arch is
      `Vehicle.v_sportbike2_arch_jackie_player` (appearance "default"). The earlier "wrong bike" was the
      pre-v0.85 spawn method, not the record; the v0.85 appearance-lockable `spawnDynEntity` spawns his
      Arch reliably. Locked into ALL vehicle flows (`Config.vehicle`/`.cruise`/`.bikeReturn.bikeRecord`).
      The B1/B2/B3 "Bike model test" harness is kept only as a fallback for a future livery regression.
- [x] **Main-quest ban (v0.62): ✅ CONFIRMED in-game (Antonia 2026-07-06)** — during a real main quest
      Jackie says bye and walks off. `isMainQuestActive()` reflection works.
      Optional (still open): give the main-quest exit a DEDICATED VO line (`Config.mainQuestExit`, currently
      the send-off line). Candidate = **"Ahí luego, V."** once its VO is scraped into the bank.
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

## 🆕 v0.65 — bike-model test: try DIFFERENT records (✅ RESOLVED — see banner) (2026-06-23)
> ✅ **RESOLVED (confirmed in-game after v0.85):** Jackie's real Arch is `v_sportbike2_arch_jackie_player`
> (appearance "default") after all. The "wrong bike" was the pre-v0.85 DES spawn method, not the record —
> the v0.85 appearance-lockable `spawnDynEntity` spawns his Arch reliably. Locked into every vehicle flow.
> B1/B2/B3 harness kept as a fallback only. Original v0.65 notes below are historical.

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
- [x] **TEST — DONE:** confirmed `v_sportbike2_arch_jackie_player` (default) is his real Arch; locked into
      the live `spawnDynEntity` bike spawn (and cruise + bike-return). B1/B2/B3 kept as a fallback tool.

## 🗒️ Session 2026-06-23b — RELEASE PLANNING + init.lua module split (DISCUSSION ONLY, no code changed)
No deploy this session. Two threads opened for later; nothing implemented yet.

### Thread 1 — Nexus / mod-manager publishing (researched, NOT started)
- **"Download with Mod Manager" is basically free** once the upload zip mirrors the game root. Vortex/MO2
  already understand Cyberpunk's layout — no custom manifest needed. Zip internal structure must be:
  - `bin/x64/plugins/cyber_engine_tweaks/mods/JackieLives/`  (init.lua, config.lua, README)
  - `r6/audioware/JackieLives/`  (manifest + audio — but see copyright blocker)
- **Dependencies = Requirements tab, NOT bundled:** RED4ext, CET, redscript, TweakXL, ArchiveXL, Codeware,
  Audioware, AMM (if hard runtime dep). Pin game patch in the description (version drift = #1 breakage).
- [x] **FOMOD installer added (2026-07-04).** `staging/fomod/info.xml` + `staging/fomod/ModuleConfig.xml`
  make Vortex/MO2 recognise the mod (no more "couldn't determine mod type / fallback installer" notice).
  No user options — both folders install 1:1 to game root. **Packaging rule:** the Nexus zip must have
  `fomod\`, `bin\`, and `r6\` at the TOP LEVEL — zip the *contents* of `staging\`, never the `staging`
  folder itself (a wrapper folder breaks FOMOD detection).
- [ ] Write `package.ps1` that builds the Nexus-ready zip (mirror-root structure, contents of `staging/`) — deferred.
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
- [x] **TEST — DONE (✅ RESOLVED, see the v0.65 banner above):** `v_sportbike2_arch_jackie_player` +
      appearance "default" spawns his correct gold Arch once the spawn is done the v0.85 appearance-lockable
      way. Locked into the live `spawnDynEntity` bike spawn (+ cruise + bike-return).

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
- **Husbando mode** switch (Relationship): OFF = Hermano (canon, with Misty); ON = Husbando (slow-burn
  with V, broke up with Misty). Sets `JL.husbando`. **v1.2: now fully wired** — see the v1.2 section below.
- **Disable vehicle arrivals** switch (Arrivals): ON forces FOOT arrival regardless of
  `Config.call.arrivalMethod`. Wired: `runCallAction` gates `bike` with `and not JL.disableVehicleArrivals`
  (the single decision point at the `arrivalMethod == "bike"` line). Default OFF (bike allowed) so it
  doesn't surprise the concurrent arrival-overhaul work; players opt in when the bike glitches.
- [x] **Persisted across saves** (`jlSaveSettings`/`jlLoadSettings`). Self-contained `key=true/false`
      store in `jl_settings.txt` in the mod folder (NO json dependency — relative `io.open`, same as the
      phone probes). Loaded in `onInit`; each switch callback saves. `JL_SETTINGS_KEYS` = the persisted
      flag list; add future toggles there.
- [x] **Hermano/Husbando = V-gender modes (v1.2, 2026-07-07):** BUILT. See the "🆕 v1.2" section below.
- [x] **Husbando-mode dialogue:** BUILT (v1.2) — Hermano overrides across talk/holocall/arrival/dismiss/
      reunion/seated; Husbando (base) slow-burn tension + Misty-split beats.
- [ ] **Husbando-mode venue schedule:** alternate `Config.daySchedules` / locations for husbando mode
      (e.g. shared apartment, different hangouts; no Misty's-shop stops). **Still open** — v1.2 did
      dialogue + recovery text + the toggle, NOT the schedule. Next pass.

## 🆕 v1.2 — Hermano/Husbando two-track relationship modes (BUILT 2026-07-07, awaiting Windows test)
**What it does:** Jackie now has two dialogue tracks. **Husbando** = female-V default (slow-burn tension
with V, more flirty, he's split with Misty). **Hermano** = male-V default (canon brother-in-arms, still
with Misty). Auto-picked from V's body gender on first load and locked; player flips it anytime in
Esc → Settings → Jackie Lives → Relationship.
- **Gender detect + first-load lock** (`init.lua`): `jlDetectGenderOnce()` runs from `onUpdate` (player
  isn't ready in `onInit`, same reason as `nsTick`), reads `GetResolvedGenderName()`, sets
  `JL.husbando = (V is Female)` and `JL.modeInit = true`, then persists. `modeInit` is in
  `JL_SETTINGS_KEYS`, so it only auto-locks ONCE; after that the saved choice / manual toggle wins.
- **Swap engine** (`init.lua`, all globals — 200-local cap respected, still 186): `jlHermano()` = is the
  male-V track active; `jlVar(entry)` returns the Hermano variant of a line/pool-entry. Resolution order:
  inline `m = {...}` on the entry, else a central **`Config.hermanoLines`** map keyed by the base sfx
  (rewrites every recurrence of a voiced line at once — e.g. the "…chica" greeting used in 5 trees).
  Injected at `Branch.start` (Jackie lines), `openChoiceMenu` (V choices, via a non-destructive copy so
  the base text is never clobbered), `pickArrivalGreetLine` (`arrivalGreetingsM`), `startLeaving`
  (`partingPoolM` + explicit-opts map, covers `mainQuestExit`), and the dinner-accept ack.
- **Config authoring** (`config.lua`): `Config.hermanoLines` map (4 voiced female-coded lines →
  cabrón/mano) + inline `m` overrides across seated/reunion/location trees + `arrivalGreetingsM` /
  `partingPoolM`. Husbando (base) text made flirtier / Misty-split on the text-only + choice lines
  (voiced barks are audio-locked — their text can't change without new clips).
- **Recovery quest, two versions** (`retrieval.lua`): Vik's tip, Jackie's shard, and the Misty + Mama
  post-reunion shards each have a Husbando (base) + Hermano (`*M`/`linesM`) version, picked by a
  `mvar()` selector fed by an injected `isHermano` mode getter (bound from `init.lua`).
- **Key design fact:** Jackie's VOICE is the same clip in both modes — the `_f_`/`_m_` tag is only the
  scene it was recorded in. So a line needs a male variant only when its CONTENT is female-coded
  (chica/mamita/flirty); content-neutral clips are reused in both. That's why the male pool being thin
  (68 clips) is fine: most of the tree is unisex. `Config.hermanoLines` IS the male/female categorization.

### Problems & Resolutions (v1.2)
- **P: Trees are compared by identity** (`bstate.tree == Config.callTree` in ~6 places) — swapping whole
  tree objects per mode would break every identity check. **R:** per-LINE overrides on the SAME tree
  objects (inline `m` + sfx-keyed map), resolved at render time. Zero identity checks touched; Husbando
  path byte-for-byte unchanged.
- **P: `openChoiceMenu` mutated `c.text` in place** (from `textPool`) — a per-mode text swap there would
  permanently clobber the base Husbando text on the first Hermano open. **R:** resolve display text into a
  shallow COPY of the choice; the config's base text is never written. (Also fixes the latent textPool clobber.)
- **P: Player not ready in `onInit`** for gender read. **R:** one-shot in `onUpdate`, retries until
  `GetResolvedGenderName()` reads, then locks — same pattern the Native Settings panel uses.

### ⚠️ Needs Windows / in-game verification (can't be checked on the Mac)
- [ ] **Gender API:** confirm `Game.GetPlayer():GetResolvedGenderName()` returns the CName `"Female"`/
      `"Male"` and the mode auto-locks correctly (check the console log line "V body gender read -> …").
      Test BOTH a female-V and a male-V save.
- [ ] **First-load lock + manual switch:** new save auto-picks by gender; toggling in Esc menu sticks and
      survives a reload; deleting `jl_settings.txt` re-triggers the auto-lock.
- [ ] **Verify the 5 male-V clips by ear** (Whisper mis-hears Spanish — every one is marked `⚠️ VERIFY`
      in `config.lua`): greeting `…cabrón`, straight-to-biz `…mano`, "man of the hour", "you with me mano",
      "make moves mano". Fix the subtitle if the clip's actual words differ.
- [ ] **Play a male-V run end-to-end:** reunion call/meet, a venue talk, a holocall summon + arrival, a
      dismiss, and walk up to Misty's + El Coyote for the post-reunion shards — all should read Hermano.

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
- [x] **Jackie's Arch livery — ✅ RESOLVED.** `v_sportbike2_arch_jackie_player` (appearance "default")
      shows his correct gold Arch once spawned the v0.85 appearance-lockable way. Locked into all flows.
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
