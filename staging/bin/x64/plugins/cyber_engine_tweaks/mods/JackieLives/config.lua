-- Jackie Lives — configuration
-- Antonia edits THIS file. Coordinates are captured in-game (see README).

local Config = {}

-- Mod version. Bump on every deploy; deploy.ps1 prints it and init.lua logs it on load.
Config.version = "1.56"

-- ---- master toggles -------------------------------------------------------
-- DEBUG: when true, the mod hooks native phone/holocall methods at load and prints a
-- [JackieLives PROBE] line whenever one fires. Open your phone + call Jackie, then read the
-- CET console to see which methods drive the call (tells us if a native hook is viable).
-- Turn OFF (false) once we're done investigating. See docs/native_phone_probes.md.
Config.probeNativePhone      = true
Config.enableSchedule        = true
Config.scheduleCheckInterval = 2.0     -- seconds between schedule/proximity checks
Config.proximityRadius       = 45.0    -- metres: idle Jackie appears when you're this close to his spot

-- ---- Banner sound (v1.x) --------------------------------------------------
-- Every native on-screen BANNER (blaze objectives, the dinner objective, call notices, refusals) plays
-- this short UI sound so it isn't silent. All banners share one helper (showOnscreenMsg) so this applies
-- universally. sfx is a base-game 2D UI sound event played on the player; set sfx = "" for silent banners.
Config.banner = {
  sfx = "ui_loot_rarity_legendary",   -- the chosen UI sound event (Antonia's pick). Set "" for silent banners.
}

-- ---- Jackie's spawn record ------------------------------------------------
-- Discover it once: spawn Jackie via AMM's menu, then click "Find Jackie" in our window.
-- The console prints  DISCOVERED Jackie record = '...'  — paste that string here and summon
-- will work directly afterwards (no AMM menu needed again).
Config.jackieRecord = "Character.Jackie"   -- discovered 2026-06-16; summon now works without the AMM menu
Config.jackieName   = "Jackie"

-- ---- Jackie's playable VOICE events (v0.11) -------------------------------
-- These are Jackie's OWN WWise events (from SoundDB's events DB). Played on his entity via
-- AudioSystem:Play, exactly like the V grunt test - but these are HIS voice, so they actually sound.
-- They are vocal efforts / barks / reactions (grunts, laughs, "greet", pain...), NOT full dialogue
-- sentences. The 777 spoken lines (String IDs in the tagger) need a different playback path.
-- Add/remove freely; the in-game "Play Jackie voice" dropdown reads this list.
Config.jackieEvents = {
  "ono_jackie_greet",
  "ono_jackie_laughs", "ono_jackie_laughs_soft", "ono_jackie_laughs_hard",
  "ono_jackie_curious", "ono_jackie_huff_emote", "ono_jackie_additional",
  "ono_jackie_effort", "ono_jackie_effort_short", "ono_jackie_effort_long", "ono_jackie_effort_big",
  "ono_jackie_attack_short", "ono_jackie_attack_long",
  "ono_jackie_pain_short", "ono_jackie_pain_long",
  "ono_jackie_bump", "ono_jackie_jump", "ono_jackie_fall", "ono_jackie_knock_down",
  "ono_jackie_choking", "ono_jackie_fear_panic_scream",
  "ono_jackie_death_short", "ono_jackie_death_long", "ono_jackie_death_last_breath",
  "ono_jackie_phone",
  -- scene VO events (may be short spoken phrases - test these):
  "vo_3d_jackie", "vo_3d_jackie_e3", "vo_q003_jackie_mumbling", "vo_q003_jackie_cybergore",
  "q201_sc_03_jackie_vo_01", "q201_sc_03_jackie_vo_02", "q201_sc_03_jackie_vo_03",
  "q005_sc_09_jackie_vo_pain_01", "q005_sc_09_jackie_vo_pain_02",
}

-- VO test: the event the "Play Jackie voice" button starts on (any name from the list above).
Config.talkTest = {
  event    = "ono_jackie_greet",
  emitter  = "",                    -- audio emitter name; try "" first, then alternatives if silent
  onPlayer = false,                 -- UI toggle: play on V (debug) vs on Jackie
}

-- ---- talk to Jackie (look at him + press the bound "Talk to Jackie" key) ---
-- Bind the key once in CET -> Bindings -> "Talk to Jackie (look at him)" -- bind it to F so it
-- matches the on-screen "[F]" prompt. Then, overlay CLOSED, look at Jackie nearby: a dialogue-box
-- prompt appears; tap F -> he grunts. (v0.13 adds the native-style prompt; see init.lua.)
Config.talk = {
  range      = 6.0,    -- metres; must be looking at Jackie within this distance (v0.39: 4->6, easier on a moving NPC)
  cooldown   = 1.5,    -- seconds between lines (anti-spam)
  rareChance = 0.05,   -- 5% chance to pull from the 'rare' pool instead of 'common'
  keyLabel   = "F",    -- prompt text; v0.15 hooks the game's native Interact key, so F works now
  logActions = false,  -- DEBUG: true -> logs every input action name on press, so we can
                       -- confirm which CName F maps to if the F-trigger doesn't fire. Off normally.
  useChoiceBox = true, -- v0.19: ON. Look at Jackie within range -> the REAL native choice BOX
                       -- "[F] Talk" appears (pushed to the interaction blackboard); look away -> it hides.
                       -- This makes the box a PERMANENT look-driven prompt, not the one-shot test button.
  boxRefresh   = 1.0,  -- seconds: re-assert the box while looking, so it survives if the game's own
                       -- interaction system clears the blackboard. 0 = push once only (no heartbeat).
}
-- On each talk: 95% -> a random 'common' event, 5% -> a random 'rare' event.
Config.talkLines = {
  common = { "ono_jackie_greet", "ono_jackie_curious", "ono_jackie_phone" },
  rare   = { "ono_jackie_bump", "ono_jackie_additional", "ono_jackie_laughs_soft" },
}

-- ---- catch-his-eye smile (v0.53) -----------------------------------------
-- When V holds their gaze straight on Jackie (look-at, within range), there's a LOW chance per roll
-- that he flashes a brief smile back, then his face relaxes. Pure facial — no audio, no dialogue —
-- so it never interrupts talking/barks (those gate it off). Smile = native FacialReaction
-- category 3 / idle 6 (5=Joy, 2=Neutral; verified). Reset via stim:ResetFacial(0).
Config.smile = {
  enabled  = true,
  chance      = 0.033, -- per-roll probability he smiles when caught looking (middle ground: 0.025 -> 0.033)
  dinnerChance= 0.04,  -- higher chance while out for dinner with him (the happy occasion; original 0.04)
  rollEvery= 1.5,    -- seconds between rolls while you keep looking at him
  duration = 3.0,    -- seconds the smile is held before his face relaxes
  range    = 8.0,    -- metres; only if V is within this distance
  cooldown = 25.0,   -- seconds after a smile before he can smile again (keeps it special)
  reapply  = 0.6,    -- re-assert the facial every N s so it doesn't decay before duration ends
  category = 3,      -- FacialReaction category for the smile set
  idle     = 6,      -- 6 = Smile — HIS OWN signature grin (5 = Joy, 2 = Neutral)
  -- v0.94 SMILE VARIETY — WHICH face a smile uses once one fires (does NOT change how OFTEN he smiles).
  -- `selfChance` of the time it's his own `idle` (the Smile); the rest of the time it's one of
  -- `otherIdles` (the "other" happy faces), picked evenly so they COLLECTIVELY share (1 - selfChance).
  -- Only 5 (Joy) is verified so far, so today it's 60% Smile / 40% Joy. To add more variety, sweep
  -- category 3 in JackieLipsync for other happy idles and append them here — they auto-split the 40%.
  selfChance = 0.60,     -- 60% his own Smile; 40% shared across otherIdles
  otherIdles = { 5 },    -- other happy faces (5 = Joy). Grow this list as more are verified.
  -- v0.93 REUNION SMILE BOOST — during the first-meeting dialogue (reunionMeetTree) he beams:
  -- a forced smile for the first `reunionForceSeconds`, then `reunionChanceMult`x the normal smile
  -- chance for the rest of that chat. `reunionIdles` rotates his two happy faces (6 = Smile, 5 = Joy)
  -- so it isn't one frozen expression. The smile always YIELDS to his mouth flap, so his spoken lines
  -- still lip-sync (the smile fills the gaps between/after his lines).
  reunionForceSeconds = 8.0,
  reunionChanceMult   = 3.0,
  reunionIdles        = { 6, 5 },   -- happy faces to rotate (Smile, Joy)
}

-- ---- ambient "feel alive" grunts (v0.55) ----------------------------------
-- While Jackie is present (your companion OR idling at a venue) and nothing else is driving his
-- voice (no talk/dialogue/call), every `everyMinutes` REAL minutes there's a small `chance` he
-- lets out ONE of his NON-PAINED vocal efforts — a laugh, a huff, a curious "hmm". Pure ambience to
-- make him feel alive. The pool below is deliberately the calm/casual events only: NO pain, choking,
-- scream, death, or combat/attack barks, so he never randomly sounds hurt or like he's fighting.
-- Played on his entity via the same WWise path as the talk grunts. enabled=false turns it off.
Config.ambientGrunt = {
  enabled      = true,
  chance       = 0.10,    -- per-roll probability he grunts (10%)
  everyMinutes = 10.0,    -- REAL minutes between rolls (so ~once every ~100 min on average)
  events = {              -- non-pained vocal efforts only:
    "ono_jackie_greet",
    "ono_jackie_curious",
    "ono_jackie_huff_emote",
    "ono_jackie_additional",
    "ono_jackie_laughs",
    "ono_jackie_laughs_soft",
    "ono_jackie_laughs_hard",
  },
}

-- ---- dialogue runner (v0.20: REAL audio via Audioware) --------------------
-- A scripted V<->Jackie exchange. Each line:
--   speaker = "V" / "Jackie"  (subtitle label)
--   text    = the subtitle shown on screen
--   sfx     = an Audioware event registered in audioware/JackieLives/JackieLives.yml
--             -> his REAL voice .ogg, played via Game.GetAudioSystemExt():Play(...)
--   dur     = fallback seconds before the next line IF the audio duration can't be read
--             (the runner asks Audioware for the real clip length and uses that).
-- MVP CAVEAT: there are NO V voice files, so V's lines reuse Jackie clips for now.
-- FUTURE: full-quality game .wem per line (see audioware manifest + TODO).
Config.testDialogue = {
  { speaker = "V",      text = "Talk to me, choomba.",                              sfx = "jl_2239163066690486272", dur = 2.5 },
  { speaker = "Jackie", text = "Don't come here often, do ya? Heheh. Good to see you, chica.", sfx = "jl_1661700260668284928", dur = 4.5 },
  { speaker = "V",      text = "How you feel? You all right?",                      sfx = "jl_1802590928224841728", dur = 2.8 },
  { speaker = "Jackie", text = "Does not get any higher, choom.",                   sfx = "jl_1660221856871665664", dur = 2.8 },
  { speaker = "V",      text = "Ready to mosey?",                                   sfx = "jl_2239013722221887488", dur = 2.2 },
  { speaker = "Jackie", text = "So let's do our thing.",                            sfx = "jl_1762127358882361344", dur = 2.5 },
}

-- ---- dialogue box display -------------------------------------------------
-- cycleHint = the key label shown in the box for "next choice". CET can't hard-set a
-- default binding in code, so bind "Jackie dialogue: next choice" in CET -> Bindings to
-- this key (you used "-") and keep this label matching it. F selects the highlighted row.
Config.dialogue = {
  cycleHint  = "Up/Dn",  -- label shown in the box; v0.33 the ARROW keys cycle by default (no binding).
  choiceHold = 2.5,      -- seconds V's chosen line stays on screen before Jackie's reply
  cycleDebug = false,    -- v0.42 OFF: arrow CNames locked + release-edge handling confirmed working.
                         --   Flip true only to re-log input-action names while a choice box is open.
}

-- ---- character-based subtitle reading time (v0.94) -----------------------
-- For the EMOTIONAL reunion beats — the phone call (reunionCallTree) and the first face-to-face
-- meeting (reunionMeetTree) — a flat 3 s subtitle flashed long lines by before they could be read.
-- When a line has no readable voice-clip length to pace by (the mute build), we instead scale the
-- subtitle's on-screen time to the LINE LENGTH:  secs = clamp(minSecs, base + chars/charsPerSec, maxSecs).
-- Lower charsPerSec = slower reading pace = lines linger longer. Applies to BOTH Jackie's lines and
-- V's chosen replies on those two trees; the rest of the mod is unchanged.
-- Anchored to feel: 1-2 word line ~2 s, a ~6-word sentence (~30 chars) ~3 s (matches the old flat
-- 3.0 s), and long lines keep stretching (~7 s at 120 chars, ~10.7 s at 200), capped at maxSecs.
Config.subtitleReading = {
  minSecs     = 2.0,   -- floor: a 1-2 word line ("Hey.") holds this long, no longer
  maxSecs     = 16.0,  -- ceiling: a very long paragraph won't sit forever
  base        = 1.6,   -- fixed lead-in added to every line (time to notice it appeared)
  charsPerSec = 22.0,  -- reading pace in characters/second (higher = shorter holds)
}

-- ---- send Jackie off (v0.33) ---------------------------------------------
-- A dialogue choice that is ALWAYS shown while Jackie is your COMPANION (following you).
-- Picking it ends the talk, Jackie says a parting line, his follower role is dropped and he
-- WALKS AWAY; once he is `despawnDistance` m from V (or `maxSeconds` pass) he despawns. This
-- is the immersive opposite of the instant "Dismiss Jackie" hotkey.
Config.dismiss = {
  choiceText      = "Head home, Jackie. I got this from here.",  -- silent V line in the choice box
  partingSfx      = "jl_1155727714874494976",   -- Jackie VO: "Time we were on our way, mamita."
  partingText     = "Time we were on our way, mamita.",
  -- v0.94 (Antonia 2026-07-06): Jackie's parting line is now a POOL — startLeaving() picks one at random
  -- each dismiss (partingText/partingSfx above stay as the safe fallback if the pool is empty). Antonia's
  -- signature walk-away line "Ahí luego, V." goes here; she says at least 3 CLEAN in-game instances exist.
  -- ⚠️ TODO(Windows/Audioware): scrape those 3 clips → add to audioware/JackieLives/JackieLives.yml → put
  -- the clip's jl_ id in `sfx` below. Until then sfx=nil = text+grunt fallback (does NOT break the bank;
  -- never invent a jl_ id — a missing .wav makes Audioware reject the WHOLE bank). Same line is the
  -- designated goodbye for the #3b story-NPC gate (see docs/story_npc_gate.md).
  partingPool     = {
    { text = "Time we were on our way, mamita.", sfx = "jl_1155727714874494976" }, -- voiced (existing)
    { text = "Ahí luego, V.",                    sfx = nil }, -- TODO sfx: 3 clean instances exist (scrape → bank)
  },
  -- v1.2: HERMANO (male-V) parting pool — used by startLeaving when the male-V track is active
  -- (jlHermano()). Text-only entries play the fallback grunt + subtitle (mute), like other Hermano
  -- lines with no clean clip. ⚠️ VERIFY any sfx by ear on Windows before trusting the subtitle.
  partingPoolM    = {
    { text = "Time we were on our way, mano." },
    { text = "Ahí luego, mano.",  sfx = nil },
    { text = "Make moves, mano.", sfx = "jl_jackie_vs_vset_jackie_m_1f119a05be52a008" }, -- ⚠️ VERIFY audio by ear
  },
  despawnDistance = 30.0,    -- metres from V he must reach before he vanishes
  movement        = "Walk",  -- "Walk" | "Run" | "Sprint" - how he leaves
  maxSeconds      = 30.0,    -- safety: despawn anyway if he hasn't reached the distance by now
}

-- ---- main-quest "excuse himself" exit (v0.62) ----------------------------
-- When V starts/tracks a MAIN quest while Jackie is tagging along, he bows out (same walk-off as
-- a normal send-off). Defaults to the send-off line so spoken VO + subtitle stay in sync. To give
-- him a DEDICATED excuse line, set `sfx` to a jl_ clip from the voice bank and `text` to its exact
-- words (so audio and subtitle match) — e.g. something like "This one's yours, hermano — go."
Config.mainQuestExit = {
  text = Config.dismiss.partingText,   -- TODO: dedicated "excuse himself" VO + matching subtitle
  sfx  = Config.dismiss.partingSfx,
}

-- ---- companion duration (v0.39) ------------------------------------------
-- Jackie won't stay a merc forever - he heads home on his own after `maxGameHours` IN-GAME
-- hours as your companion (timer measured in game time, not real time). Asking him to dinner
-- (Config.date) RESETS that clock. Set autoLeaveOnExpiry=false to disable the auto-departure.
Config.companion = {
  maxGameHours      = 6.0,   -- in-game hours he'll tag along before heading home on his own
  autoLeaveOnExpiry = true,  -- when the clock runs out he walks off (reuses the send-off exit)
}

-- ---- companion PERSISTENCE (v0.72) ----------------------------------------
-- "Is Jackie your companion right now?" is saved INSIDE each save slot as the game fact
-- jackielives_companion (the same per-save fact mechanism the retrieval quest uses for its stage).
-- Because it lives in the save (not a global file), loading an OLD save where Jackie WASN'T with you
-- simply finds the fact unset -> he is NOT wrongly restored. companionPersistTick watches that fact:
-- if it says "companion" but no live Jackie exists — a fresh load wiped the runtime state, or a
-- load-screen fast-travel culled his body (the case Config.catchUp can't recover) — it re-spawns and
-- re-promotes him at V's side. Set enabled=false to go back to "he's gone after a reload".
-- ⚠️ v0.84b: DISABLED AGAIN — still breaks the save. The v0.84 world-ready + AMM gate did NOT fix it:
-- on test (2026-07-02) Jackie spawns VISIBLY in V's face on the FIRST frame after loading, then the game
-- crashes. So the respawn is firing immediately (the grace is being skipped) AND the settle-hide isn't
-- catching him. Leading hypothesis: on an in-session load onUpdate keeps running and playerPos() never
-- reads nil during the transition, so worldReadyAt is a STALE pre-load stamp -> the 8 s grace has
-- "already elapsed" -> spawn on frame 1. Real fix likely needs a genuine load EVENT (hook a save-load /
-- player OnGameAttached) to reset worldReadyAt, not an inferred nil-gap; and/or spawn HIDDEN and only
-- reveal once fully streamed. Deferred — see TODO "🐞 v0.84b persist still breaks the save". Stays OFF.
Config.persist = {
  enabled       = false,  -- ⚠️ still crashes the save on load (v0.84b) — see warning above; do not flip on
  startupGrace  = 8.0,    -- s of settled, in-world time (from when the player appears) before we spawn
  gapSustain    = 1.5,    -- s the "should be here but isn't" condition must hold (rides out stream hiccups)
  cooldown      = 5.0,    -- s between respawn attempts (also covers the spawn->promote resolve window)
}

-- ---- walk-abreast (v0.85b) — DEFAULT companion behaviour ------------------
-- A settled companion Jackie holds a spot BESIDE / slightly AHEAD of V instead of trailing — the "walk
-- next to me" feel, everywhere (not just the dinner outing). Tuned in-game by Antonia and now ON by default.
-- How it behaves:
--  * WALK-ONLY. Only active while V WALKS (her slow toggle). At jog/sprint he falls back to the normal
--    trail (V has 3 speeds, Jackie 2 — he can't out-pace a jogging V). Thresholds: walkMaxSpeed/jogMinSpeed.
--  * CLOSEST SIDE. `angleRight` / `angleLeft` are the two near-front anchors; he takes whichever is closer
--    to him (with `sideHysteresis` stickiness) so he doesn't cut across in front of V.
--  * SMOOTH heading (EMA over `smoothSeconds`) so the anchor drifts, never snaps on a camera twitch.
--  * ANGULAR LEASH (v1.36 — replaces the old chase-an-exact-point model that jittered). Jackie ambles
--    inside a WIDE zone (`zoneRadius`) around his side anchor, walking FORWARD with V (target led ahead by
--    `leadDistance`) at walk pace — no fighting for a precise spot. His hurdle to SPRINT is deliberately
--    high: he only sprints when he drifts into the REAR ARC behind V (`rearArcFrac` of the full circle,
--    centred directly behind her). Then he sprints up to the set angle and, once back inside `zoneRadius`,
--    CALMS to a walk again — and stays walking until he falls behind into the rear arc once more.
-- Angle values are FRACTIONAL dial steps (of `positions`). Pace + zone knobs live in the CET pace tuner.
Config.abreast = {
  enabled        = true,    -- v0.85b: ON by default for a companion (Antonia confirmed it feels great)
  positions      = 12,      -- steps in the full dial the fractional angles are measured in
  angleRight     = 0.85,    -- near-front on V's RIGHT (Antonia's tuned value)
  angleLeft      = 11.25,   -- near-front on V's LEFT  (Antonia's tuned value)
  sideHysteresis = 0.6,     -- m the other side must be closer by before he switches sides (anti-flip-flop)
  radius         = 3.5,     -- metres from V he holds — FALLBACK only; the live value is jlFollowDistance()
  -- v1.55 FLEXIBLE DISTANCE BAND (Antonia: "the abreast follow should be more flexible on the distance:
  -- anything from 1.2m to 5m is ok"). The old model rebuilt his anchor at EXACTLY `radius` every re-issue,
  -- so any drift in or out was actively corrected — he was forever being tugged back onto one precise ring.
  -- Now, if he's ALREADY somewhere inside [minRadius, maxRadius], that distance is accepted and the anchor
  -- is rebuilt AT HIS CURRENT DISTANCE — we only correct the ANGLE (keep him beside her, not behind). He's
  -- pulled back toward the nominal radius only when he strays outside the band entirely. Net effect: he
  -- ambles anywhere from brushing-your-shoulder to a few metres out, and stops fighting for a spot.
  minRadius      = 1.2,     -- m — closer than this and he's crowding V -> push him back out to nominal
  maxRadius      = 5.0,     -- m — further than this and he's drifting away -> pull him back in to nominal
  smoothSeconds  = 3.3,     -- EMA time-constant for V's heading (Antonia's tuned value)
  interval       = 0.3,     -- s between re-issues of the move-to-anchor command (short = tracks the drift)
  movement       = "Walk",  -- how he moves while HOLDING position (matches V's walk)
  -- v1.36 ANGULAR LEASH. The old distance-chase jittered; now the SPRINT trigger is purely ANGULAR.
  -- rearArcFrac = the slice of the full 360° circle (centred DIRECTLY BEHIND V) that counts as "he's fallen
  -- behind" and unlocks a sprint. 0.40 -> the rear 144° (he must be >108° off V's forward). zoneRadius = the
  -- free-walk leash around the side anchor: he sprints in until within it, then calms to a walk and holds
  -- (desiredDistance while holding == zoneRadius, so he doesn't fight for the exact spot). leadDistance pushes
  -- his WALK target ahead of the anchor along V's heading so he strolls forward WITH her, not stop-start.
  rearArcFrac    = 0.40,    -- rear slice of the circle (behind V) that permits a sprint (bigger = sprints sooner)
  zoneRadius     = 1.5,     -- m free-walk leash around the anchor; sprint ends + hold-tolerance = this
  leadDistance   = 2.0,     -- m his WALK target sits ahead of the anchor (along V's heading) so he keeps moving
  catchUpMovement= "Sprint",-- how he moves to GET into position when he's fallen behind (must out-pace a walking V)
  catchUpSmoothSeconds = 0.5, -- while sprinting in, aim at a near-INSTANT heading (where V is NOW), not the EMA
  catchUpTolerance = 0.35,  -- target distance while sprinting in
  -- v1.39: pace-match (SetIndividualTimeDilation speed-up) REMOVED — scaling his time made his stride float
  -- and broke the angular leash. He now just walks his own natural Walk gait; the rear-arc sprint handles
  -- keeping up. Players who dislike walk-beside can turn it off entirely (Esc -> Settings -> Jackie Lives ->
  -- Gameplay -> "Walk beside me"), which reverts him to the plain trailing follower (JL.disableCustomWalk).
  walkMaxSpeed   = 2.0,     -- m/s at/below which V counts as WALKING (abreast on)
  jogMinSpeed    = 2.8,     -- m/s above which V counts as jogging/sprinting (trail); band = hysteresis
  -- v0.93: abreast is a NARROW case — it only makes sense while V is genuinely STROLLING. Two extra gates
  -- stop it from hijacking normal standing-around conversation (where he'd sit at a weird 3.5 m angle,
  -- jerking as the camera pans):
  walkMinSpeed      = 0.6,  -- m/s V must EXCEED to count as walking. Below this she's STILL -> he trails close.
  walkSustainSeconds= 2.0,  -- s V must hold the walk band CONTINUOUSLY before abreast engages (no snap on a step)
  -- v1.46 VERTICAL GATE (stairs / slopes / ladders / lifts). Walking abreast is a FLAT-GROUND idea: a
  -- staircase is rarely two-abreast wide, and the old build copied V's z straight into the anchor, so the
  -- point 5.5 m "ahead" of a climbing V was buried inside the stairs (or floating over them). The nav
  -- projection then flip-flopped between the lower and upper floor each re-issue — that is the "jagged
  -- teleport in front of V" on stairs. Two independent triggers drop him back to the single-file trail:
  --   * slopeRate  — V's own |dz/dt| (smoothed): she's climbing/descending right now.
  --   * maxZDelta  — Jackie is already this far above/below V (he's on a different step/landing).
  -- releaseSeconds keeps the trail latched briefly after the climb ends, so a landing mid-staircase (or a
  -- single step off a kerb) can't flip him back and forth between trail and abreast.
  slopeRate         = 0.45, -- m/s of V's vertical speed above which we call it a slope/stairs (a jump also trips it)
  maxZDelta         = 1.0,  -- m of Jackie-vs-V height difference that means "not on the same floor"
  slopeReleaseSeconds = 1.5,-- s the trail stays latched after V levels out (anti flip-flop on landings)
  -- GROUND THE ANCHOR. Even on a gentle ramp the anchor must sit on the walkable surface, not at V's z.
  -- We snap it down onto the human navmesh; if the snap lands more than maxAnchorZDelta from V it's a
  -- different floor (a balcony/metro deck the downward search found) -> reject it and keep V's z.
  maxAnchorZDelta   = 2.5,  -- m the navmesh-snapped anchor may differ from V's height before we distrust it
}

-- ---- stealth / sneaking (v1.46) -------------------------------------------
-- When V CROUCHES, walking abreast is exactly wrong: it parks Jackie 3.5 m out to the side and slightly
-- AHEAD of her — straight into the enemy's vision cone she is trying to stay out of. (Antonia, in-game:
-- "he crouches right into the enemy who then detects him.") So sneaking flips him into a SHADOW: he drops
-- behind V, single-file, at `followDistance`, and never leads.
--
-- Detection is by NAME, not by a hardcoded enum number: `gamePSMLocomotionStates` member names are resolved
-- through jlAnimEnum() at first use and cached. If a name ever stops resolving (a game patch renames it) the
-- lookup degrades to "not sneaking" — the pre-v1.46 behaviour — and says so once in jackie_debug.log rather
-- than erroring. `locomotionStates` is the list we treat as "V is sneaking".
Config.stealth = {
  enabled        = true,
  -- PSM Locomotion state names that mean "V is crouched". Confirmed against `gamePSMLocomotionStates`
  -- (psmImports.script): Default=0, Crouch=1, Sprint=2, Kereznikov=3, Jump=4, Vault=5, Dodge=6, DodgeAir=7,
  -- Workspot=8, Slide=9, SlideFall=10, CrouchSprint=11, CrouchDodge=12. The game's own crouch indicator
  -- treats the crouch FAMILY as {Crouch, CrouchDodge, Slide}; we take the three deliberate ones and leave
  -- Slide out (a slide is a sprint manoeuvre, not sneaking). Resolved BY NAME at runtime, never hardcoded.
  locomotionStates = { "Crouch", "CrouchSprint", "CrouchDodge" },
  followDistance = 3.0,     -- m he trails BEHIND V while she sneaks (single file, never abreast)
  movement       = "Walk",  -- his gait while shadowing (never Run — he'd clatter past her into the cone)
  -- There is NO crouch entry in `moveMovementType` (Walk/Run/Sprint only). The crouched gait comes from the
  -- `alwaysUseStealth` BOOL on the follow command: its handler pushes the NPC into the Stealth high-level
  -- state, which is what actually makes him sneak. Set false if the crouched walk ever looks wrong.
  stealthGait    = true,
}

-- ---- Blaze finale "transport calm" (v1.51) --------------------------------
-- At full black the finale holsters V's weapon, clears combat and force-stands her (uncrouch). That fired
-- ONCE, in the same frame as V's async teleport — a race, and the log claimed success either way.
-- Now it re-asserts on a heartbeat until V is OBSERVED standing (read from the PlayerStateMachine
-- Locomotion blackboard via jlVCrouched), then reports how long it took, or says plainly that it failed.
-- v1.53: the ForceStand record is minted at runtime (blazeEnsureForceStandRecord) — no TweakXL. If that ever
-- fails, the uncrouch is simply SKIPPED: V stays crouched through the transport and the finale runs normally.
-- That is the agreed fallback; do NOT reintroduce a framework dependency to fix cosmetics.
Config.blazeCalm = {
  holdSeconds         = 3.0,   -- keep re-asserting for this long, or until V is seen standing
  interval            = 0.25,  -- s between re-asserts (and between crouch checks)
  maxHolsterReasserts = 3,     -- re-queue the holster at most this many times (the state we land in can re-draw)
}

-- ---- follower takedown (v1.47, MVP) ---------------------------------------
-- The Heist's "Jackie takes down the second guard while V takes the first" is NOT a cutscene. It is one
-- parameterised AI command issued to Jackie, confirmed in the decompiled scripts:
--
--   class AIFollowerTakedownCommand extends AIFollowerCommand   -- core/ai/aiCommand.script:761
--     targetRef                      : EntityReference
--     approachBeforeTakedown         : Bool
--     doNotTeleportIfTargetIsVisible : Bool
--     target                         : weak<GameObject>
--
-- AIFollowerTakedownCommandHandler.Update (ai/Tasks/FollowerTasks.script:146) checks `target` FIRST and only
-- falls back to resolving the quest-authored `targetRef` NodeRef. So from Lua we set `.target` to any live
-- NPC handle and never touch targetRef. The handler then sets the `CombatTarget` behaviour arg and calls
-- NPCPuppet.ChangeHighLevelState(jackie, Stealth) — the follower behaviour tree's takedown subtree plays the
-- real grapple. We never script the animation. (That is why q005 waits on `BaseStatusEffect.Grappled`.)
--
-- ⚠️ PREREQUISITE: the takedown task only EXISTS inside the Follower role's behaviour tree. Jackie must be a
-- genuine player companion (AI role Follower + FriendlyTarget = player) — exactly what AMM's companion
-- promotion sets, and what jlCompanionCheck() verifies. Same prerequisite as the enemy-perception immunity.
--
-- ⚠️ NOVEL: no CET mod anywhere is known to construct this command. The class is RTTI-registered and the
-- send route is the same native SendCommand we already use, so it *should* work — but it is UNPROVEN in Lua.
-- Hence `auto = false`: v1.47 ships the manual look-at test button ONLY. Once Antonia confirms in-game that
-- Jackie really grapples the target, the opportunistic trigger gets built on top of this exact call.
--
-- The only target gates in the handler are ScriptedPuppet.IsActive(target) and not IsBeingGrappled(target).
-- There is NO "must be unaware" check in script — but the grapple that plays is a stealth takedown, so an
-- alerted target may fall through to normal combat instead. Test on an unaware guard first.
--
-- v1.48 — WHY THE FIRST ATTEMPT DID NOTHING (Antonia: "the NPC survived"). Two independent bugs:
--
--  1. `combatCommand` was left FALSE. The game's own takedown order — PlayerPuppet.OnTakedownOrder
--     (player.script:3744) — builds the very same class and sets `takedownCommand.combatCommand = true`
--     before broadcasting it. `AIFollowerCommand.IsCombatCommand()` has NO script callers, so the flag is
--     read natively by the follower behaviour tree to route the command into its combat/takedown subtree.
--     Without it the command is accepted and then quietly ignored — exactly the observed symptom.
--     (Note the sibling class `AIFollowerCombatCommand` exists ONLY to `default combatCommand = true`.)
--
--  2. WE were cancelling it. followKeepCloseTick re-asserts an AIFollowTargetCommand every
--     `Config.follow.interval` (1.5 s) and abreastTick an AIMoveToCommand every 0.3 s. A takedown needs
--     several seconds to walk over and play the grapple, so our own leash clobbered it mid-approach.
--     `holdCommands` now freezes the follow/abreast/catch-up ticks for the duration.
--
-- The game delivers this through PlayerSquadInterface.BroadcastCommand, but that only fans the command out
-- to each squad member via GiveCommandToSquadMember -> the same SendCommand we already call. Sending it
-- straight to Jackie is equivalent and does not require him to be in V's combat squad.
Config.takedown = {
  auto = false,             -- v1.47: opportunistic auto-takedown NOT built yet — prove the command first
  approachBeforeTakedown         = true,  -- he walks up to the victim; false = snap straight behind them
  doNotTeleportIfTargetIsVisible = true,  -- never teleport him while the victim is on V's screen (ugly)
  combatCommand                  = true,  -- v1.48: REQUIRED. Routes it into the follower BT's takedown subtree.
  -- v1.48 SAFETY (Antonia asked). Nothing here ever deals damage — the engine owns the grapple — but a
  -- takedown ordered on V or on a friendly would still be wrong. Refuse anything that isn't a hostile puppet.
  requireHostile   = true,  -- only order takedowns on NPCs hostile to V. Set false at your own risk.
  -- v1.48 while a takedown runs, our leash ticks must not re-issue commands to Jackie or they cancel it.
  holdCommands     = true,
  timeoutSeconds   = 15.0,  -- give up (and hand him back to the leash) if no grapple/kill lands by then
}

-- ---- companion catch-up teleport (v0.66) ----------------------------------
-- Once Jackie is a SETTLED companion (arrived, role applied, not dismissed/expired), if V gets far
-- away — FAST-TRAVEL, a long sprint, or he just got left behind — he teleports back to V's SIDE.
-- This is the immersive "a companion never gets lost" behaviour. It is DELIBERATELY off during the
-- arrival walk-in / dinner / walk-off (those own his movement and must not be yanked). He always lands
-- a few metres to V's side on the navmesh, never on top of her. Set enabled=false to turn it off.
-- NOTE: this only works while his runtime body still EXISTS. A load-screen fast-travel can cull a
-- spawned NPC entirely — that case is now handled by Config.persist (companionPersistTick re-spawns him).
-- ⚠️ v0.79: the AITeleportCommand aiTeleport() uses can only relocate his body while it's still STREAMED
-- and its AI is live. A load-screen fast-travel across DISTRICTS leaves his body stranded/unstreamed far
-- away (his handle still resolves — that's how we read "1994 m" — but the teleport silently no-ops, so the
-- old build logged "teleported to her side" while he stayed put; travelling back never recovered him).
-- So: beyond respawnDistance, OR if a teleport already fired but failed to close the gap (maxTeleTries),
-- catchUpTick DESPAWNS the stranded body and RESPAWNS a fresh Jackie at V (respawnCompanionAtV). This runs
-- 2 s+ AFTER the fast-travel with V fully in-world, so it does NOT hit the persist-on-LOAD crash (Config.persist).
Config.catchUp = {
  enabled         = true,
  distance        = 25.0,   -- metres from V beyond which he's considered "left behind"
  sustainSeconds  = 2.0,    -- he must stay that far for this long (rides out a fast-travel/load gap)
  cooldown        = 3.0,    -- minimum seconds between catch-up teleports (anti-thrash)
  placeDistance   = 3.0,    -- metres to V's side he's dropped (navmesh-snapped; never ON V)
  -- v1.40: on both recovery paths, place him AHEAD/beside V (reusing the walk-abreast angles), never BEHIND —
  -- the wall/structure behind a fast-travel point is where the old build dropped him. The teleport path uses
  -- frontSideArrivalPoint directly; the respawn path repositions him there (invisibly) during the settle-hide
  -- window. Set false to go back to AMM's own drop spot + the plain side/behind navmesh sweep.
  frontSideRespawn = true,
  respawnWhenStranded = true,-- v0.79: fall back to despawn+respawn when a teleport can't reach him (set false to disable)
  respawnDistance = 150.0,  -- metres beyond which we skip the doomed teleport and respawn immediately (district-scale FT)
  maxTeleTries    = 1,      -- consecutive teleports that fail to close the gap before we escalate to a respawn
}

-- ---- respawn settle-in (v0.82) --------------------------------------------
-- When catch-up (or persist) RESPAWNS Jackie at V after a fast-travel, AMM drops a fresh body ~1 m from
-- her — which V sees POP into existence and which can spawn against a wall. settleTick hides him +
-- disables his collision for a brief window right after the respawn, then reveals him where he settled and
-- restores collision (a follower must always collide). Timings are seconds from the respawn. hideSeconds
-- < collideSeconds so he's already visible while the extra collision-off grace lets him nudge free of any
-- geometry. Set enabled=false to go back to an instant (popping) respawn.
Config.respawnSettle = {
  enabled        = true,
  hideSeconds    = 2.0,   -- keep him invisible this long after the respawn (hides the pop-in)
  collideSeconds = 4.0,   -- keep his collision OFF this long (so he can't spawn stuck in a wall)
}

-- ---- keep-close follow (v0.67) --------------------------------------------
-- After arrival we hand Jackie to AMM's companion follow, but AMM uses a LONG leash, so he trails
-- far behind V. This re-asserts OUR tight follow on a throttle so he holds `distance` metres instead.
-- `distance` is how far back he keeps (a few m — under your ~4 m target, with margin so he doesn't clip
-- V when she stops). `interval` is how often we re-assert (lower = stickier/closer but more commands;
-- raise it or set enabled=false if he ever looks jittery). Only runs while he's a settled companion.
Config.follow = {
  enabled  = true,
  -- v1.55: this is now only the FALLBACK. The live trail distance comes from jlFollowDistance() — the
  -- "Jackie's follow distance" slider in Esc -> Settings, which drives BOTH this trail and the walk-abreast
  -- radius from one number (Antonia: "the default distance for sprint follow and abreast follow can be the
  -- same right? Like 3-5m?"). Default is Config.followDistanceDefault below (3.5 m), up from the old 1.5.
  distance = 3.5,    -- metres he keeps behind V — fallback if the slider value is somehow unreadable
  interval = 1.5,    -- seconds between follow re-asserts
  movement = "Run",  -- "Walk" | "Run" | "Sprint" — how he closes the gap when he drifts back
}

-- ============================================================================
-- EASTER EGG (v1.55) — REVEREND FLASH's refund, in the bar at Rocky Ridge
-- ============================================================================
-- Reverend Flash is a YouTuber who play-tested the mod and, with no fast-travel out there, paid **3,847
-- eddies** of his own to get himself to Rocky Ridge. If he (or anyone) plays it again, the bar beside the
-- garage pays him back TENFOLD — and hands Jackie's Arch back on top.
--
-- WHERE (Antonia, captured in-game): **behind the bar, in the BD shack next to the gas station** — the gas
-- station being where Jackie's note is found. It sits ~42 m south-west of the note and 1.7 m higher.
--
-- Fires on PROXIMITY, once per save, and is INDEPENDENT of the questline (it works at any stage). Two
-- separately-latched triggers on the same spot, so collecting the money doesn't spend the hidden thank-you.
--
-- ⚠️ WHY `radius` IS SMALL (5 m, not the 20 m first drafted). The payout is 38,470 eddies — a serious sum.
-- At 20 m the zone covered the whole shack, so ANY player poking around Rocky Ridge (which the questline
-- sends them to) would have collected it, and "the mod hands you 38k eddies" is the kind of thing Nexus
-- reviewers call game-breaking. Antonia's answer: keep it exactly where she stood — BEHIND the bar — because
-- "the other mod players will never go to that exact spot". 5 m honours that: you have to actually walk
-- behind the bar, but you don't have to stand on a precise pixel. Reverend Flash gets his refund; a passer-by
-- doesn't trip over it.
--
-- ⚠️ WHAT IT ACTUALLY GIVES: **eddies straight into your inventory** (`Items.money`) — NOT a lootable
-- world item and NOT a shard you pick up. A physical money shard means spawning a world entity and wiring
-- its loot table, which is fragile from CET; Antonia okayed cash if the shard wasn't easy. So it's cash:
-- instant, safe, and impossible to miss or lose.
Config.revflash = {
  enabled      = true,
  pos          = { 2548.57, -31.076, 82.609 },   -- behind the bar, in the BD shack by the gas station
  radius       = 5.0,     -- m — you have to go BEHIND the bar. Deliberately small; see the note above.
  noticeRadius = 0.5,     -- m — the tight, hidden spot where the tribute card appears

  -- The payout: 3,847 eddies spent -> 38,470 back (10x).
  spent        = 3847,
  eddies       = 38470,
  moneyItem    = "Items.money",
  factMoney    = "jackielives_revflash_paid",     -- one-time latch: the payout
  factNotice   = "jackielives_revflash_thanked",  -- one-time latch: the tribute card

  -- Give Jackie's Arch back too. UNDOES whatever removed it (jlReturnJackiesBike disables the vehicle
  -- record); we simply re-enable it. Skipped if V already has it — see revflashRestoreBike in retrieval.lua.
  restoreBike  = true,

  bannerText   = "Something's been left here for you...",   -- native banner when the payout lands
  noticeTitle  = "Jackie Lives — thank you, Reverend Flash",
  -- The note states the amount, as Antonia asked ("your ... eddies returned 10 fold").
  noticeText   = "You paid 3,847 eddies out of your own pocket to ride all the way out to Rocky Ridge — just "
              .. "to find out whether Jackie was really still breathin' out here. Then you went and told the "
              .. "world about it.\n\nSo here's your 3,847 eddies back, returned TEN FOLD: 38,470. And Jackie's "
              .. "Arch with it.\n\nNobody puts in road miles like that for a mod they don't love. Gracias, "
              .. "Reverend. — Jackie & the Jackie Lives team",
}

-- ---- Misty, retired (v1.55 — Husbando only) -------------------------------
-- In Husbando, the FIRST time Jackie is at Misty's Esoterica is the last: that's where they break up, and
-- he never goes back. The break-up is never spoken (v1.54 cut every line about it) — it's shown, by him
-- simply never being at her shop again. From then on that schedule slot resolves to the noodle bar instead.
-- Hermano is untouched: they're solid, and his Misty visits carry on forever.
-- Both keys are `Config.locations` keys; the swap happens in currentScheduleBlock (init.lua).
Config.mistyKey            = "misty"    -- the venue that retires (Husbando)
Config.mistyReplacementKey = "noodle"   -- what that slot becomes afterwards

-- ---- follow-distance slider (v1.55) ---------------------------------------
-- ONE number, set in Esc -> Settings -> Jackie Lives -> Gameplay, that drives how far away Jackie sits in
-- BOTH follow modes: the trail (followKeepCloseTick, while V jogs/sprints) and walk-abreast (his side
-- anchor while V strolls). Persisted as a float — see JL_SETTINGS_NUMS in init.lua.
Config.followDistanceDefault = 3.5   -- m — the slider's default + reset value
Config.followDistanceMin     = 1.2   -- m — slider floor
Config.followDistanceMax     = 8.0   -- m — slider ceiling

-- ---- ask Jackie to dinner / a date (v0.41 - restaurant walk) -------------
-- While Jackie is your COMPANION, the talk menu offers a dinner invite. V then picks a specific
-- restaurant; the mod sets a MAP WAYPOINT there (white dot) + a blue on-screen OBJECTIVE, keeps
-- Jackie following, and when V ARRIVES (<seatTriggerRadius) Jackie walks to HIS seat, plays the
-- sit anim, waits, says one line, and the companion clock FULLY RESETS (once per 24 in-game hours).
-- When V walks off (>getUpRadius) Jackie gets up, says a line, and re-follows. He stays our
-- companion (never despawns) the whole time. No quest/WolvenKit - a Lua state machine (dinnerTick).
Config.date = {
  inviteText           = "Wanna get something to eat?",  -- the menu option (V's invite)
  unlockAfterGameHours = 1.0,    -- the invite only appears after this long together...
  enforceUnlock        = true,   -- v0.55: ON — dinner invite only unlocks after 1 in-game hour together.

  seatTriggerRadius = 12.0,  -- metres: V this close to the spot -> Jackie peels off to his seat
  seatReachRadius   = 2.0,   -- metres: Jackie this close to his seat -> snap + sit
  seatTimeout       = 12.0,  -- v0.44 seconds: if he can't path within seatReachRadius by now, snap+sit anyway
  sitWaitSeconds    = 2.0,   -- seconds seated before he says his line + the clock resets
  getUpRadius       = 10.0,  -- metres: V this far from seated Jackie -> he gets up + re-follows
  resetCooldownHours = 24.0, -- the dinner FULL reset can only fire once per this many in-game hours
  objectiveText       = "Grab some food with Jackie: Go to %s",   -- neon-left flash when the walk starts (%s = place)
  objectiveTextDrinks = "Grab some drinks with Jackie: Go to %s",  -- v1.x: used for bars (restaurant with drinks=true)
  objectiveDuration   = 6.0,                                       -- seconds the flash stays up

  venuesShown       = 4,     -- v0.52: only this many RANDOM venues (of the full pool) are offered per picker

  -- Restaurants V can pick. pos/yaw reuse coords already captured in Config.locations (his bar/stall
  -- waypoints) so he sits facing the right way. Each entry WITH pos auto-becomes a dialogue option.
  -- pickText/pickSfx (v0.52): Jackie's spoken line when HE picks this spot (the "You pick, hermano." path).
  -- Only venues WITH a pickSfx are eligible for his self-pick, so he can actually NAME where they're going.
  restaurants = {
    { key = "noodle",    name = "the noodle bar", pos = { -1441.064, 1257.748,  23.090 }, yaw =  -87.1 },  -- noodle bar
    { key = "redwood",   name = "Redwood Market", pos = {  -431.550,  669.948, 115.010 }, yaw =  -33.5 },  -- "noodle place" stall
    { key = "afterlife", name = "Afterlife",      pos = { -1449.437, 1012.129,  17.357 }, yaw = -168.3, drinks = true,  -- barstool, right side (bar -> "drinks")
      pickText = "...then I say we hit the Afterlife, hahaha... You know, do some shots.", pickSfx = "jl_1790891785270616064" },
    { key = "ginger",    name = "Ginger Panda",   pos = {  -485.426,  576.939,  31.302 }, yaw =  -17.1 },  -- the bar
    { key = "lizzies",   name = "Lizzie's Bar",   pos = { -1174.427, 1572.135,  23.115 }, yaw =  -68.5, drinks = true,  -- rear bar (bar -> "drinks")
      pickText = "Meet me at Lizzie's.", pickSfx = "jl_1691270077089771520" },
  },

  -- v0.43: walk/arrival BANTER fully disabled (Antonia). The only spoken beats are the three below.
  -- Jackie's single-line beats (real-matching clips; the restaurant NAME shows via the waypoint + objective):
  ackText    = "Right on, chica.",                  ackSfx    = "jl_1721407637774192672",  -- on accept (heading out)
  doneText   = "Anyway, what's goin' on?",          doneSfx   = "jl_1878047791342612480",  -- v0.48: seated, 2s after sitting (reset) — relaxed catch-up beat
  getUpText  = "Why, what's the rush?",             getUpSfx  = "jl_1989527454849245184",  -- V walks off -> he gets up
  -- v0.43b/v0.47: he won't go out to eat twice a day. If asked within resetCooldownHours of his last
  -- dinner, he REFUSES the moment V invites him (before the venue picker shows) and the outing aborts.
  -- v0.48: "Got no time for this!" was unsuitable -> DROPPED. Placeholder reuses the decline line until a
  -- better "already ate today" clip is chosen from the refreshed (~1000-line) bank. (See TODO backlog.)
  refuseText = "Why, what's the rush?", refuseSfx = "jl_1989527454849245184",

  -- v0.48: JACKIE drops a hungry HINT himself (not just V's menu invite). While he's your companion and a
  -- dinner is available (off cooldown), after a randomized in-game gap he simply SAYS this line — no picker,
  -- no choices. It nudges V to use her own "Wanna get something to eat?" invite. The gap sits close to his
  -- max summon time so it lands like an occasional "I'm gettin' hungry", not a nag. enabled=false disables.
  jackieInvite = {
    enabled           = true,
    text              = "C'mon, let's go have some lunch.",
    sfx               = "jl_1834500545020096512",
    minGapGameMinutes = 140.0,  -- earliest he'll hint after a fresh companion session / the last hint
    maxGapGameMinutes = 175.0,  -- latest; the actual gap is random in [min,max] in-game minutes
  },

  tree = {
    start = "open",
    nodes = {
      -- v0.52: V's "Wanna get something to eat?" lands -> Jackie ACCEPTS ("had enough for one day"), then the
      -- venue picker shows RIGHT HERE: 4 random venues (withDateChoices) + "You pick, hermano." (he names a
      -- spot) + "Actually... raincheck." (-> decline). Raincheck now lives IN the picker, not a step before it.
      open = {
        jackie  = { text = "Yeah, had enough for one day, lemme tell you.", sfx = "jl_1697051347046326272" },
        restaurantPicker = true,   -- 4 random restaurant options are auto-injected here from `restaurants`
        choices = {
          { text = "You pick, hermano.",     to = nil, action = "dine:random" },
          { text = "Actually... raincheck.", to = "decline" },
        },
      },
      decline = {
        jackie  = { text = "Why, what's the rush?", sfx = "jl_1989527454849245184" },
        choices = { { text = "(Maybe next time.)", to = nil } },
      },
    },
  },

  -- v0.83: SEATED small-talk tree — used ONLY while Jackie is seated at dinner (JL.dinner.phase ==
  -- "seated"; wired via currentTalkTree). Casual banter + a few random-chance "get it off your chest"
  -- topics (each choice carries a `chance`, re-rolled every time the menu opens, so the options vary).
  -- No dismiss option here (that crashes a seated puppet). "Enough chillin'..." runs action "dinner_leave"
  -- AFTER his reply, which makes him stand + re-join as your companion (dinnerTick handles the stand-up).
  -- These lines are text-only (no sfx yet) — they play the fallback grunt + subtitle on the mute build;
  -- wire real jl_ clips later. Add/reword topics freely; every topic path ends back at "open" or "leave".
  seatedTree = {
    start = "open",
    nodes = {
      open = {
        jackiePool = {
          { text = "Man, this hits the spot. No gigs, no gunfire — just you an' me." },
          { text = "Could get used to this quiet-life thing, y'know?" },
          { text = "Good to just sit a minute, huh, chica?",
            m = { text = "Good to just sit a minute, huh, hermano?" } },
          { text = "Anyway... what's on your mind, V?" },
        },
        choices = {
          { text = "You ever miss the merc life, Jackie?",        to = "merc",      chance = 0.6 },
          { text = "This city's been grindin' me down lately.",   to = "nightcity", chance = 0.6 },
          { text = "Think Arasaka ever pays for what they did?",  to = "arasaka",   chance = 0.5 },
          { text = "How're things with you and Misty?",           to = "misty",     chance = 0.6 },
          { text = "Enough chillin', let's get movin'.",          to = "leave" },
        },
      },
      merc = {
        jackiePool = {
          { text = "Miss it? Some days. The rush, the crew... but it took more than it gave, V. You know that better'n anyone." },
          { text = "The life? Nah. The good runs, maybe. Not the endings — we both seen how those go." },
        },
        choices = {
          { text = "Yeah. We made it out, though.", to = "open"  },
          { text = "Let's get movin'.",             to = "leave" },
        },
      },
      nightcity = {
        jackiePool = {
          { text = "Night City don't care if you live or die, chica. All you can do is find your people and hold on tight.",
            m = { text = "Night City don't care if you live or die, mano. All you can do is find your people and hold on tight." } },
          { text = "This town chews everybody up. Trick's not lettin' it swallow ya whole. You got me, I got you — that's the trick." },
        },
        choices = {
          { text = "Guess that's enough.", to = "open"  },
          { text = "Let's get movin'.",    to = "leave" },
        },
      },
      arasaka = {
        jackiePool = {
          { text = "'Saka? Heh. Big fish like that never pays, V. But we're still breathin' and they don't know our names. That's a win." },
          { text = "Corpo rats always land on their feet. Best revenge's livin' good — like right now, full plate in front of us." },
        },
        choices = {
          { text = "Livin' good. I'll drink to that.", to = "open"  },
          { text = "Let's get movin'.",                to = "leave" },
        },
      },
      misty = {
        -- v1.54: Misty and Jackie are TOGETHER, in both tracks — the old "we ended it" breakup (and the
        -- "thinkin' 'bout someone else entirely" line aimed at V) is gone for good. Jackie never discusses
        -- his relationship falling apart, because it doesn't. No `m` override needed: this is his answer
        -- whichever track you're on.
        jackiePool = {
          { text = "Misty's my anchor, V. Keeps me lookin' up when I wanna look down. Dunno what I'd be without her." },
          { text = "Me an' Misty? Solid. She reads them cards, says the stars got a plan. I just tell her she's my plan." },
          { text = "She sat with Mama every week I was gone, y'know. Every week. Ain't never gonna be able to pay that back." },
        },
        choices = {
          { text = "She's good for you.",  to = "open"  },
          { text = "Let's get movin'.",    to = "leave" },
        },
      },
      leave = {
        -- terminal (no choices) + action -> after his line, dinnerTick stands him up + re-follows.
        jackiePool = {
          { text = "Heh, alright. Let's roll, chica.",
            m = { text = "Heh, alright. Let's roll, hermano." } },
          { text = "Yeah, we got a city to look after. Vamonos." },
          { text = "Right behind ya, hermano. Let's move." },
        },
        action = "dinner_leave",
      },
    },
  },
}

-- ============================================================================
-- HERMANO (male-V) LINE MAP — the male/female/unisex categorization, made executable.
-- ============================================================================
-- Jackie's VOICE is the same clip in both modes; a line only needs a male variant when its
-- CONTENT is female-coded — the pet-names (chica/mamita) or a flirty beat. This table maps
-- each such base (Husbando) line, BY ITS sfx KEY, to the Hermano replacement, and init.lua's
-- jlVar() swaps it in EVERYWHERE that clip plays at once — so the "...chica" greeting is fixed
-- here once, not in all five trees that reuse it. Lines NOT listed are UNISEX (content-neutral)
-- and reused as-is in both modes. (Individual nodes/choices can still carry an inline `m = {...}`
-- for one-off overrides — see the reunion/seated trees; that inline `m` wins over this map.)
--   • entry WITH `sfx` = real MALE-V audio from the 68-clip male pool. ⚠️ Whisper mis-hears
--        Jackie's Spanish (cabrón/mano/hermano), so each subtitle is a cleaned best-guess —
--        VERIFY BY EAR on Windows (tagger) and fix the text if the clip actually differs.
--   • entry TEXT-ONLY = no clean male clip yet -> subtitle + the neutral fallback grunt (mute),
--        exactly like the existing text-only reunion beats. Add an `sfx` later if a clip turns up.
Config.hermanoLines = {
  -- signature greeting  "...chica."  ->  "...cabrón."  (real male-V mirror clip)
  ["jl_1661700260668284928"] = { text = "Don't come here often, do ya? Good to see you, cabrón.",
                                 sfx  = "jl_jackie_q000_m_170f8b95404ea000" },   -- ⚠️ VERIFY audio by ear
  -- "Straight to biz, eh, chica?"  ->  "...mano?"  (real male-V mirror clip)
  ["jl_1777946122915868672"] = { text = "Straight to biz, eh, mano?",
                                 sfx  = "jl_jackie_q003_m_18ac88942e2ef000" },   -- ⚠️ VERIFY audio by ear
  -- parting  "Time we were on our way, mamita."  ->  a VOICED male-V parting (never "mamita" to a
  -- male V). Uses the real male clip "Make moves, mano." (same clip as partingPoolM below).
  ["jl_1155727714874494976"] = { text = "Make moves, mano.", sfx = "jl_jackie_vs_vset_jackie_m_1f119a05be52a008" },  -- ⚠️ VERIFY audio by ear
  -- gig/dinner accept  "Right on, chica."  ->  "Right on, mano."  (text-only)
  ["jl_1721407637774192672"] = { text = "Right on, mano." },
}

-- ---- branching dialogue tree (v0.23) -------------------------------------
-- A small node graph. Each node: Jackie speaks `jackie` (real voice + subtitle), then a
-- CHOICE BOX of player options appears. Choices are SILENT text (like the game's own
-- dialogue wheel) - so the missing V audio doesn't matter. Selecting a choice jumps to
-- its `to` node (Jackie's next line) or ends the conversation when to = nil.
-- sfx = an Audioware event (jl_<string_id>) from the converted 777-line bank.
Config.dialogueTree = {
  start = "open",
  nodes = {
    open = {
      jackie  = { text = "Don't come here often, do ya? Heheh. Good to see you, chica.", sfx = "jl_1661700260668284928" },
      choices = {
        { text = "How you been, Jackie?", to = "howbeen" },
        { text = "Got a gig - you in?",   to = "gig"     },
        { text = "Just passin' through.", to = "bye"     },
      },
    },
    howbeen = {
      jackie  = { text = "Does not get any higher, choom.", sfx = "jl_1660221856871665664" },
      choices = {
        { text = "Good to hear. Let's roll.", to = "gig" },
        { text = "Take it easy, hermano.",     to = "bye" },
      },
    },
    gig = {
      jackie  = { text = "So let's do our thing.", sfx = "jl_1762127358882361344" },
      choices = {
        { text = "Let's go.", to = nil },   -- end (later: trigger the summon)
      },
    },
    bye = {
      jackie  = { text = "Time we were on our way, mamita.", sfx = "jl_1155727714874494976" },
      -- v0.81: no (Leave) menu — this is the last line, so it auto-closes the dialogue box.
    },
  },
}

-- ---- location-based talk trees (v0.32) -----------------------------------
-- When you press F on Jackie, the mod picks the tree for WHERE HE CURRENTLY IS
-- (his idle-spawn location key). Same node format as Config.dialogueTree above.
-- Keys must match Config.locations keys (noodle/coyote/afterlife/misty/...).
--
-- `everywhere` is the BACKUP: used whenever he's NOT at one of these named places
-- (e.g. summoned/following you, or idling somewhere with no tree of its own). It is
-- deliberately SHORT — 2 choices, short voice lines — and carries `cooldownSeconds`:
-- once you finish it, it's marked DONE and goes on that cooldown. Press F again within
-- the cooldown and Jackie just GRUNTS (no dialogue). After it expires, the short
-- exchange is available again. Named-location trees have NO cooldown (repeatable).
--
-- jackiePool = pick one of these at random for variety (real voice + subtitle).
-- Choices are SILENT V text, so they can say anything location-flavored for free.
Config.locationDialogue = {

  -- NOODLE BAR (daytime, casual, food) ---------------------------------------
  noodle = {
    start = "open",
    nodes = {
      open = {
        jackiePool = {
          { text = "Don't come here often, do ya? Heheh. Good to see you, chica.", sfx = "jl_1661700260668284928" },
          { text = "C'mon, let's go have some lunch.",                              sfx = "jl_1834500545020096512" },
          { text = "V, how you feel? You all right?",                              sfx = "jl_1802590928224841728" },
        },
        choices = {
          { text = "What's good here?",                to = "food"  },
          { text = "How's the quiet life treatin' ya?", to = "quiet" },
          { text = "Just grabbin' a bite. Later.",      to = "bye"   },
        },
      },
      food = {
        jackie  = { text = "Does not get any higher, choom.", sfx = "jl_1660221856871665664" },
        choices = {
          { text = "Heh. Save me a stool.",             to = "bye" },
          { text = "Got a little side gig, you up for it?", to = "gig" },
        },
      },
      quiet = {
        jackie  = { text = "Eh, you know how it is, can't complain. But we ain't here to shoot the shit about me.", sfx = "jl_1861666308579323904" },
        choices = {
          { text = "Fair. Take it easy, hermano.", to = "bye" },
          { text = "Could use you on a side job.", to = "gig" },
        },
      },
      gig = {
        jackie  = { text = "So let's do our thing.", sfx = "jl_1762127358882361344" },
        choices = { { text = "Let's roll.", to = nil, action = "recruit_here" } },
      },
      bye = {
        jackie  = { text = "Time we were on our way, mamita.", sfx = "jl_1155727714874494976" },
        -- v0.81: no (Leave) menu — this is the last line, so it auto-closes the dialogue box.
      },
    },
  },

  -- EL COYOTE COJO (Mama Welles' bar — family, drinks, afternoon) -------------
  coyote = {
    start = "open",
    nodes = {
      open = {
        jackiePool = {
          { text = "Don't come here often, do ya? Heheh. Good to see you, chica.",  sfx = "jl_1661700260668284928" },
          { text = "Mama told me things come to those who wait, and some're even good!", sfx = "jl_2008342351712284672" },
          { text = "Talk to me, choomba.",                                           sfx = "jl_2239163066690486272" },
        },
        choices = {
          { text = "Mama Welles around?", to = "mama"  },
          { text = "Pour me one?",        to = "drink" },
          { text = "Just passin' through.", to = "bye" },
        },
      },
      mama = {
        jackie  = { text = "She's my blood, all right. Coyote's her dive.", sfx = "jl_1834417684413870080" },
        choices = {
          { text = "Family's everything. Later, hermano.",  to = "bye" },
          { text = "When you're done playin' barkeep, got a side gig.", to = "gig" },
        },
      },
      drink = {
        jackie  = { text = "Andale, let's drink.", sfx = "jl_2251854480654123008" },
        choices = {
          { text = "Heh. To the quiet life.",         to = "bye" },
          { text = "One drink, then I got work. You in?", to = "gig" },
        },
      },
      gig = {
        jackie  = { text = "So let's do our thing.", sfx = "jl_1762127358882361344" },
        choices = { { text = "Let's go.", to = nil, action = "recruit_here" } },
      },
      bye = {
        jackie  = { text = "Time we were on our way, mamita.", sfx = "jl_1155727714874494976" },
        -- v0.81: no (Leave) menu — this is the last line, so it auto-closes the dialogue box.
      },
    },
  },

  -- AFTERLIFE (merc legends bar, night — bittersweet, he's out of the life) ---
  afterlife = {
    start = "open",
    nodes = {
      open = {
        jackiePool = {
          { text = "Hey, V, you alive? How's things in the viper pit?", sfx = "jl_1691260805748551680" },
          { text = "Legends are born here.",                            sfx = "jl_1904093608424787968" },
          { text = "Straight to biz, eh, chica?",                       sfx = "jl_1777946122915868672" },
        },
        choices = {
          { text = "You miss it? The merc life?", to = "miss"  },
          { text = "Drink to old times?",         to = "drink" },
          { text = "Just soakin' it in. Later.",  to = "bye"   },
        },
      },
      miss = {
        jackie  = { text = "It's the biz, V. Everyone's got blood on their hands. You deal with it, you move on.", sfx = "jl_1625819953367019520" },
        choices = {
          { text = "You earned the quiet. Take it easy.", to = "bye" },
          { text = "Then do one last easy one, side gig, with me.", to = "gig" },
        },
      },
      drink = {
        jackie  = { text = "Heheh, I'll drink to that!", sfx = "jl_1806735035231395840" },
        choices = {
          { text = "To Jackie Welles. Later, choom.", to = "bye" },
          { text = "Now help me run a quick side job.", to = "gig" },
        },
      },
      gig = {
        jackie  = { text = "So let's do our thing.", sfx = "jl_1762127358882361344" },
        choices = { { text = "Let's go.", to = nil, action = "recruit_here" } },
      },
      bye = {
        jackie  = { text = "Time we were on our way, mamita.", sfx = "jl_1155727714874494976" },
        -- v0.81: no (Leave) menu — this is the last line, so it auto-closes the dialogue box.
      },
    },
  },

  -- MISTY'S ESOTERICA (calm, spiritual, his girl Misty) ----------------------
  misty = {
    start = "open",
    nodes = {
      open = {
        jackiePool = {
          { text = "Don't come here often, do ya? Heheh. Good to see you, chica.", sfx = "jl_1661700260668284928" },
          { text = "Ah, thanks, Misty. You're the best.",                          sfx = "jl_1255773314399088640" },
        },
        -- v1.54: V's lines here were rewritten so each one actually SETS UP the real voiced reply that
        -- follows it (Miguel's clips are fixed — the question has to earn the answer). Misty stays very
        -- much in the picture: this is his girl's shop and he talks about her like it.
        choices = {
          { text = "So what's the plan for the rest of your day?", to = "her"   },
          { text = "Did Misty see it comin'? You makin' it out?",  to = "cards" },
          { text = "I'll leave you to it.",                        to = "bye"   },
        },
      },
      her = {
        -- voiced: he's off to find Misty. V's question above ("what's the plan?") now flows straight in.
        jackie  = { text = "Now I go back, find Misty and we do somethin' to make me feel alive again.", sfx = "jl_1677043911795367936" },
        choices = {
          { text = "Then go feel alive, hermano. Tell her I said hey.", to = "bye" },
          { text = "Before you do — got a side gig, if you're up for it.", to = "gig" },
        },
      },
      cards = {
        -- voiced: "Misty knew... Misty always knows..." — reads as an answer now that V asked whether she
        -- foresaw him surviving, instead of the old "she read your cards yet?" non-sequitur.
        jackie  = { text = "Misty knew... Misty always knows...", sfx = "jl_2024290835469197312" },
        choices = {
          { text = "Spooky. Later, choom.",              to = "bye" },
          { text = "Cards say you'll help me on a job?", to = "gig" },
        },
      },
      gig = {
        jackie  = { text = "So let's do our thing.", sfx = "jl_1762127358882361344" },
        choices = { { text = "Let's go.", to = nil, action = "recruit_here" } },
      },
      bye = {
        jackie  = { text = "Time we were on our way, mamita.", sfx = "jl_1155727714874494976" },
        -- v0.81: no (Leave) menu — this is the last line, so it auto-closes the dialogue box.
      },
    },
  },

  -- EVERYWHERE (BACKUP: short 2-option exchange; DONE -> 60s grunt-only cooldown)
  everywhere = {
    start = "open",
    cooldownSeconds = 60,   -- after finishing this once, F just grunts until 60s pass
    nodes = {
      open = {
        -- v0.47: "Don't come here often..." is a FIXED-LOCATION greeting (proximity/meet-at-his-spot)
        -- only — it makes no sense when he's your companion after a call, so it's dropped from here.
        -- v0.48: "Anyway, what's goin' on?" moved to the dinner SEATED beat; a casual greeting sits here.
        jackiePool = {
          { text = "Talk to me, choomba.",            sfx = "jl_2239163066690486272" },
          { text = "V, how you feel? You all right?", sfx = "jl_1802590928224841728" },
          { text = "¿Qué onda?",                      sfx = "jl_2015561179233951744" },
        },
        -- v0.81: the sign-off shows a RANDOM line from its textPool (re-rolled every open, like the
        -- jackiePool above), so it never sounds canned. v1.3: the "take care / checkin' in" branch was
        -- dropped — as a companion send-off only the "let's move" lines read right, so just that pool
        -- remains (leads to his "time we were on our way" reply, `bye`).
        choices = {
          { textPool = {
              "We should get movin'.",
              "Let's get goin', hermano.",
              "Alright, I'm headin' out.",
              "Time to hit the road, choom.",
            }, to = "bye"  },
        },
      },
      bye = {
        jackie  = { text = "Time we were on our way, mamita.", sfx = "jl_1155727714874494976" },
        -- v0.81: no (Leave) menu — this is the last line, so it auto-closes the dialogue box.
      },
    },
  },
}

-- ---- HOLOCALL: call Jackie onto a gig (v0.28) ----------------------------
-- "Calling Jackie..." (ring) -> he picks up -> the SAME branching choice box runs a
-- short CALL tree (below) -> if you ask him onto a gig, the call ends and `spawnDelay`
-- seconds later Jackie SPAWNS at `spawnDistance` metres from V and WALKS IN (companion AI
-- paths him to you). This is OUR voiced dialogue box dressed as a call - NOT the native
-- phone UI - so no death-flag / contact unlock is needed (see docs/DESIGN.md, TODO).
-- A real native holocall (portrait/video) is a separate, much larger WolvenKit task.
Config.call = {
  ringSeconds   = 2.3,   -- native ring (IncomingCall) plays this long, then we abort + connect
  asleepRingSeconds = 7.0,  -- v0.55: if Jackie's ASLEEP (Config.secret window), the call rings this long then hangs up — no pickup
  ringEvent     = "ono_jackie_phone",  -- extra WWise ring SFX layered on ("" = silent)
  spawnDelay    = 5.0,   -- seconds after the call ends before Jackie spawns (v0.55: 2x back to 5.0)
  -- ============================================================================
  -- ARRIVAL METHOD — v0.50: TWO modes only (down from 3). Cycled live in the CET window.
  --   "foot" = ON-FOOT (the default). DES-spawn Jackie DIRECTLY at `Config.vehicle.spawnDistance`
  --            (50 m), SPRINT in, swap to a WALK for the last `Config.vehicle.sprintToWalk` m,
  --            promote to COMPANION at `companionDistance`, then he holds `followDistance` + stops.
  --   "bike" = his Arch + Jackie spawn at `Config.vehicle.bikeSpawnDistance` (60 m), he mounts, rides in,
  --            slows at `slowDownDistance` (30 m), PARKS on the road + dismounts at `dismountDistance`
  --            (20 m), then WALKS the rest to companion.
  -- BOTH go through vehicleArrivalTick + the shared promoteToCompanion. v0.50 DELETED the old
  -- "safe" AMM-spawn-near-V + hide + teleport walk-in entirely — DES needs no invisibility hack
  -- (Jackie spawns out at distance, never pops near V), and the slow all-the-way "walk" mode is gone
  -- (too slow). This is the big complexity collapse: one spawn backend (DES), one arrival tail.
  -- ============================================================================
  arrivalMethod        = "bike",   -- "foot" | "bike" (default = bike, per Antonia)
  vehicleSpawnDelay    = 2.0,   -- seconds after the call ends before the foot / bike Jackie spawns (back to 2.0 per Antonia)
  -- He spawns navmesh-snapped (NavigationSystem) so he never lands inside a wall/object, in the rear
  -- arc when `spawnBehind`. While approaching he is a PASSIVE DES NPC (no follower role) so the AMM
  -- companion catch-up TELEPORT can't yank him to V; he becomes a real companion only at `companionDistance`.
  -- PLACEMENT (v0.52): spawnSides=true (default) spawns him on a SIDE of V — left or right, 90°±20° off
  -- V's facing, random side (the other side is a fallback if the first has no valid navmesh spot). Still
  -- obeys the navmesh + same-level (`maxSpawnZDelta`) rules. Set false to use the old `spawnBehind` arc.
  spawnSides       = true,
  spawnBehind      = true,   -- only used when spawnSides=false: rear arc (true) vs front (false)
  approachMovement = "Run",  -- movement tier the COMPANION uses to close to followDistance after handoff
  arriveDistance   = 3.0,    -- metres from V the sprint/walk MoveTo aims to stop short of him
  followDistance   = 1.6,    -- metres the COMPANION keeps after handoff (so he doesn't clip into V)
  -- HANDOFF: promote to a real companion (combat + follow) once within this. KEEP IT SMALL: AMM's
  -- SetNPCAsCompanion enables a catch-up TELEPORT, so promoting while he's still far (e.g. 18 m) can
  -- visibly YANK him into V. v0.50 dropped it to 5 m so he's basically arrived before the teleport
  -- ever becomes available -> no yank, no running-into-V. Then the grunt fires at arrivalGruntDistance.
  companionDistance    = 5.0,    -- m: promote to companion at this range (foot + bike)
  arrivalGruntDistance = 4.0,    -- m: once companion + this close, Jackie says an arrival GREETING line (below)

  -- v0.52: on arrival (once he closes to arrivalGruntDistance) Jackie speaks a real GREETING LINE — a jl_
  -- clip + subtitle, NOT a WWise grunt event. The picker avoids the last-used line + any used in the last
  -- 5 min (JL.bark.greetRepeatCooldown). Add/trim entries freely; any jl_<id> from the bank works.
  arrivalGreetings = {
    { text = "Talk to me, choomba.",        sfx = "jl_2239163066690486272" },
    { text = "¿Qué onda?",                  sfx = "jl_2015561179233951744" },
    { text = "Got me right behind you.",    sfx = "jl_1679806464288055296" },
    { text = "So? You ready?",              sfx = "jl_1902765821582520320" },
    { text = "V, hey! ¿Cómo te sientes?",   sfx = "jl_1867549271199477760" },
  },

  -- v1.2: HERMANO (male-V) arrival greetings — pickArrivalGreetLine uses this pool when the male-V
  -- track is active. Mixes real male-V clips with a couple of unisex ones reused from above.
  -- ⚠️ VERIFY the male clips by ear on Windows (Whisper mis-hears the address terms) and fix text.
  arrivalGreetingsM = {
    { text = "Man of the hour! Took you long enough — worked up an appetite just waitin'.", sfx = "jl_jackie_q001_m_15c159da7a325000" }, -- ⚠️ VERIFY
    { text = "Straight to biz, eh, mano?",  sfx = "jl_jackie_q003_m_18ac88942e2ef000" },          -- ⚠️ VERIFY
    { text = "Hey, you with me, mano?",     sfx = "jl_jackie_vs_vset_jackie_m_1b4957a4724e2004" }, -- ⚠️ VERIFY
    { text = "Make moves, mano.",           sfx = "jl_jackie_vs_vset_jackie_m_1f119a05be52a008" }, -- ⚠️ VERIFY
    { text = "Talk to me, choomba.",        sfx = "jl_2239163066690486272" },  -- unisex clip, reused
    { text = "So? You ready?",              sfx = "jl_1902765821582520320" },  -- unisex clip, reused
  },
}

-- ---- VENUE HELLO — first approach of each in-game day (v1.41) ---------------
-- Walking up to an IDLE Jackie at one of his venues, the FIRST time on a given in-game day, makes him
-- call out a real spoken hello (jl_ clip + subtitle) at `range` metres — the way a choom clocks you
-- across the bar. Every later approach that day falls through to the ordinary WWise greet grunt
-- (JL.bark.greetEvents), so he doesn't recite a full line every time you walk past his stool.
--
-- "Day" is the absolute in-game day (jlGameDay() = floor(total game seconds / 86400)), so it survives
-- sleeping/fast-travel and doesn't rely on catching a midnight wrap while the mod is loaded.
--
-- ⚠️ Every `sfx` here MUST exist in audioware/JackieLives/JackieLives.yml or Audioware rejects the WHOLE
-- bank and Jackie goes silent. All six below are verified present.
Config.venueGreet = {
  enabled = true,
  range   = 5.0,   -- m: he calls out once V is this close (bark grunt range stays 6 m)

  -- Female-V / default track. `jl_1661700260668284928` is the f-side of the same source line as the
  -- m-side clip below, so the pair reads identically across genders.
  greetings = {
    { text = "Don't come here often, do ya? Heheh. It's good to see you, chica.", sfx = "jl_1661700260668284928" },
    { text = "Hey, V – you alive? How's things in the viper pit?",                sfx = "jl_1691260805748551680" },
    { text = "Chica! Finally!",                                                   sfx = "jl_2008322358689853440" },
    { text = "¿Qué onda?",                                                        sfx = "jl_2015561179233951744" },
  },

  -- v1.2 HERMANO (male-V) track — real male clips where they exist, unisex clips reused otherwise.
  greetingsM = {
    { text = "Don't come here often, do ya? Heheh. It's good to see you, cabrón.", sfx = "jl_jackie_q000_m_170f8b95404ea000" },
    { text = "Hermano, finally!",                                                  sfx = "jl_jackie_q113_m_1bdefe8b702ef000" },
    { text = "Hey, V – you alive? How's things in the viper pit?",                 sfx = "jl_1691260805748551680" },  -- unisex clip, reused
    { text = "¿Qué onda?",                                                         sfx = "jl_2015561179233951744" },  -- unisex clip, reused
  },
}

-- ---- ARRIVAL TUNING — foot + bike (v0.34, unified v0.50) --------------------
-- The two arrival modes (Config.call.arrivalMethod) share this block and ONE state machine
-- (vehicleArrivalTick). Both finish with the SAME sprint -> walk -> companion tail:
--   "foot" — DES-spawn Jackie at `spawnDistance` (50 m), SPRINT in, downshift to WALK for the last
--            `sprintToWalk` m, promote at Config.call.companionDistance.
--   "bike" — Arch + Jackie spawn at `bikeSpawnDistance` (60 m), he mounts + rides in at `cruiseSpeed`
--            (re-targeting V every `retargetInterval`); at `slowDownDistance` (30 m) he eases to
--            `slowSpeed`, PARKS the bike on the road + dismounts at `dismountDistance` (20 m), then just
--            WALKS the rest. A STUCK FAILSAFE bails him to foot if the bike truly can't path (disabled
--            while he's deliberately slowing); the fresh-respawn FOOT FALLBACK is OPT-IN (footFallback).
Config.vehicle = {
  spawnDistance     = 50.0,  -- FOOT: metres from V Jackie spawns at (navmesh-snapped), then sprints in
  -- BIKE spawn distance: 60 m (was 80). 80 m let him path so far out he could leave the streamed/
  -- rendered zone and stall; 60 m keeps the whole ride on-screen while still giving room to ride + brake.
  bikeSpawnDistance = 60.0,
  sprintToWalk      = 14.0,  -- Jackie->V distance where he downshifts sprint -> walk (FOOT only; last 14 m — v0.55)
  arriveDistance    = 3.0,   -- Jackie->V distance the foot/walk MoveTo aims to stop short of him
  -- --- VALID-SPAWN GUARD + STUCK->RESPAWN LADDER (v0.51) ---
  -- The spawn point is rejected unless it's on the human navmesh AND within `maxSpawnZDelta` of V's
  -- height, so he can't land on a roof / balcony / metro level / parking deck (wrong floor = usually
  -- no walkable path). If he STILL can't path in (stutters in place, no progress for
  -- `respawnStuckSeconds`), he's despawned + respawned at the next-closer `respawnRungs` distance.
  -- At the closest rung he's on V's own navmesh, so it converges; beyond it, he just hands off in place.
  maxSpawnZDelta    = 4.0,   -- m: max |Jackie.z - V.z| for a valid spawn point (same floor as V)
  -- v0.53: rungs end at 20 m, NOT 5 m — a 5 m respawn read as a "teleport to V's face". 20 m is still a
  -- clean walk-in, and with the BEHIND fallback in the spawn picker the ladder rarely needs to fire at all.
  respawnRungs      = { 35.0, 20.0 },  -- progressively-closer respawn distances when stuck
  respawnStuckSeconds = 10.0,-- v0.52: seconds of no forward progress (to V) before a stuck-respawn fires (2x; was 5 — too tight)
  respawnProgressEps  = 1.0, -- m: distance he must shave off his closest-so-far to count as "progress"
  -- --- BIKE KNOBS (used by "bike" arrival) ---
  bikeRecord       = "Vehicle.v_sportbike2_arch_jackie_player",  -- Jackie's real (gold) Arch — test-confirmed
  -- Appearance "default" spawns his correct gold Arch livery on the v0.85 appearance-lockable spawn
  -- path (bike-record hunt RESOLVED). If a livery regression ever appears, the CET "Bike model test"
  -- read-back reveals the exact appearance name to pin here.
  bikeAppearance   = "default",
  mountSeconds     = 4.0,    -- v0.53: seconds to let Jackie walk to the seat + climb on BEFORE the bike drives off
  fellOffDist      = 6.0,    -- v0.53: if Jackie is >this from the moving bike, the mount failed -> he walks in on foot
  cruiseSpeed      = 8.0,    -- drive speed (8 = careful; he was reckless at higher)
  slowDownDistance = 30.0,   -- bike->V distance at which he eases off to slowSpeed (brakes smoothly)
  slowSpeed        = 3.0,    -- m/s drive speed once inside slowDownDistance, so the park isn't a hard stop
  dismountDistance = 20.0,   -- bike->V distance at which he parks the bike (on the road) + gets off, then WALKS in
  retargetInterval = 3.0,    -- re-issue the drive at V's latest position (longer = less re-path stutter)
  -- STUCK FAILSAFE: if the bike crawls (< stuckSpeed m/s) for stuckSustain s, after a stuckGrace beat
  -- at the start (he's still climbing on), he parks early + walks in on foot. Covers dense areas where
  -- the bike can't path. v0.52: DISABLED while he's inside slowDownDistance (a deliberate crawl near the
  -- stop was tripping it), and the timers doubled so a brief snag at a light no longer ditches the bike.
  stuckSpeed       = 1.0,    -- m/s; below this = likely stuck
  stuckGrace       = 8.0,    -- v0.52: seconds after mounting before stuck-detection starts (2x; was 4)
  stuckSustain     = 10.0,   -- REAL seconds of crawling before he bails off the bike (lenient — traffic lights hold 7s+)
  -- TWO independent safety timers (they fire at DIFFERENT times + do DIFFERENT things):
  --   maxSeconds (120) = LAST RESORT. Force the companion handoff in place (no respawn) — may use
  --                      AMM's catch-up teleport. Always armed.
  --   fallbackSeconds (40) = (ONLY if footFallback=true) ditch the bike, DESPAWN bike+Jackie and
  --                      RESPAWN him fresh ~fallbackDistance m out on foot, then sprint/walk in.
  -- v0.47: footFallback DEFAULTS OFF — it was firing at 40s and killing legit bike rides (an 80 m
  -- city ride routinely takes >40s) which is what "broke" bike arrivals since v0.38. Off = the bike
  -- rides uninterrupted like it did in the working v0.36; maxSeconds is the only backstop.
  footFallback     = false,  -- true = re-enable the 40s ditch-bike-and-respawn-on-foot rescue
  maxSeconds       = 120.0,  -- LAST RESORT: force companion handoff if the whole arrival stalls
  fallbackSeconds  = 40.0,   -- (footFallback only) no handoff by now -> fresh on-foot respawn
  fallbackDistance = 40.0,   -- metres from V the fresh Jackie spawns at, then sprints/walks in
}

-- V's hang-up sign-offs. At the end of any call strand one of these is shown as V's last line
-- (text only — V has no voice, so these are free to add) then the call hangs up. Add freely.
Config.callFarewells = {
  "Later, choom.",
  "Catch you on the flip side.",
  "Stay frosty, hermano.",
  "See ya, Jackie.",
  "Talk soon.",
  "Keep your phone on, yeah?",
  "Preem. Out.",
  "Don't keep me waitin'.",
  "Be safe out there.",
  "Adios, choomba.",
  "Catch you later.",
  "Nova. Later, hermano.",
}

-- NATIVE phone call (v0.29 experiment). We drive the game's real holocall UI via
-- PhoneSystem:TriggerCall (discovered by probing — see docs/native_phone_probes.md). The
-- call id is a quest phone-call CName: "jackie" (alive) shows his avatar + connects;
-- "jackie_dead" is the dead-state call (rings, no connect). Phases: IncomingCall(1) =
-- ringing, StartCall(2) = connected/avatar live, EndCall(3) = hang up. mode Video(2) = holo.
Config.nativeCall = {
  id                = "jackie_dead", -- quest phone-call CName for the call (avatar source)
  hijackPlayerCalls = true,          -- when the PLAYER calls Jackie from the in-game phone, route that
                                     --   call into our flow (immersive). Observes PhoneSystem:TriggerCall.

  -- v1.55 THE REAL FIX for the "temporarily unavailable" flash. The old hijack was an `Observe` on
  -- PhoneSystem.TriggerCall — a POST-hook, so the vanilla call (and its quest fact, and therefore its
  -- scene) had ALREADY started by the time we reacted. Everything after that was catch-up; that race is
  -- why the dead card kept flashing. `preemptCall` instead OVERRIDES PhoneSystem.OnTriggerCall — the
  -- handler that runs BEFORE the call starts — and simply doesn't let the vanilla Jackie call begin.
  --   preemptCall        = true  -> pre-empt (recommended; falls back to the old Observe if it can't register)
  --                        false -> use the old racing Observe (only if the pre-empt ever misbehaves)
  --   suppressStatusText = true  -> also swallow the "number temporarily unavailable" TEXT while our call runs
  -- Both are written to FAIL OPEN: anything we can't positively identify as a Jackie call runs vanilla.
  preemptCall        = true,
  suppressStatusText = true,

  -- v1.56 THE "SEMI-SMART IDENTIFIER" (Antonia's idea, and it's the right one). We do NOT depend on knowing
  -- the engine's exact parameter names/order/arity — which we cannot verify without a Windows machine, and
  -- which changes between game patches anyway. Instead the Override stringifies EVERY argument it is handed
  -- and keyword-matches. If any of them names Jackie (or a dead/disconnected number), it's our call.
  -- Matching is case-insensitive and literal (no Lua patterns), so these are safe to edit freely.
  -- ⚠️ Keep them SPECIFIC. A keyword that also appears in someone else's contact would swallow THEIR call.
  -- Every phone call the mod sees is logged once, so the CET log shows exactly what these are matching.
  jackieKeywords = { "jackie", "jackie_dead", "disconnected", "unavailable" },
  useNativeWindow   = true,          -- ON (Antonia's design): RING (IncomingCall ~2s) -> STOP (EndCall,
                                   --   aborts the canned native call) -> CONNECT (StartCall, the empty
                                   --   transparent window) -> our branching voice convo runs over it ->
                                   --   random V farewell -> hang up (EndCall). false = text "Calling..." only.

  -- v1.33 "temporarily unavailable" FIX (live-tunable in the CET "Call fix" section; these are the
  -- persisted DEFAULTS). When the player dials Jackie, the game rings the DEAD contact (jackie_dead),
  -- which flashes the "number temporarily unavailable" card before we take over. hijackMode picks how
  -- we kill it:
  --   "quick"   = let the dead ring play `hijackHangupDelay` s, then EndCall -> connect (short card).
  --   "instant" = EndCall the dead ring immediately, then connect — no ring, no unavailable card.
  --   "alive"   = EndCall the dead card, ring the ALIVE `jackie` avatar instead, then connect. <- DEFAULT.
  --   "vanilla" = don't hijack (A/B baseline — you hear the game's own call).
  -- v1.37 (Antonia in-game test): "alive" is the WINNER — RING/CONNECT on the live `jackie` contact
  -- shows the see-through holo and NEVER triggers the "temporarily unavailable" card (only the DEAD
  -- contact does). The dead/disconnected call is INTENTIONALLY kept for early game: the hijack only
  -- engages once the retrieval quest reaches the shard-read stage (AWAITING), so before that V really
  -- does get "number disconnected" (immersive — Jackie's still believed dead). See setupCallHijack.
  hijackMode        = "alive",
  hijackHangupDelay = 0.75,           -- seconds (quick mode): how long the dead ring plays before connect
  hijackOurRingSfx  = false,          -- quick/instant: ALSO play our ring SFX? false avoids "rings twice"
  aliveId           = "jackie",       -- the alive-contact CName used by hijackMode="alive"
  -- v1.37: the alive contact's IncomingCall is SILENT, so we play our own ring SFX (Config.call.ringEvent)
  -- and randomise how long it rings before Jackie "picks up" — feels human, not a fixed beat.
  alivePickupMin    = 1.2,            -- seconds: shortest ring before he answers (alive mode)
  alivePickupMax    = 3.0,            -- seconds: longest ring before he answers (alive mode)
}

-- The CALL conversation. Same node format as Config.dialogueTree. A choice may carry
-- action = "summon_arrival" -> when that choice ends the call, the delayed spawn fires.
Config.callTree = {
  start = "ring",
  nodes = {
    -- Jackie's line on each node is picked at random from `jackiePool` (real voice + subtitle),
    -- for variety. Pools seeded from the 777-line scan (tools/voice-tagger/classify_out.json);
    -- add more {text, sfx="jl_<id>"} freely — any id from audioware/JackieLives/index.json works.
    ring = {
      -- Greeting when he picks up the call. `chance` on a line = rare independent roll for it;
      -- the rest are picked uniformly (see pickPoolLine in init.lua). v0.34b adds the extra
      -- call-appropriate greetings from docs/conversations.md (skipped the physical/face-to-face
      -- ones - "Catch, chica!", "Huh?", "Leave it to me, I'm drivin'" - they don't fit a phone call).
      jackiePool = {
        { text = "Talk to me, choomba.",                                         sfx = "jl_2239163066690486272" },
        { text = "Hey V - you alive? How's things in the viper pit?",            sfx = "jl_1691260805748551680" },
        { text = "Straight to biz, eh, chica?",                                  sfx = "jl_1777946122915868672" },
        { text = "V, hey! Como te sientes?",                                     sfx = "jl_1867549271199477760" },
        { text = "Que onda?",                                                    sfx = "jl_2015561179233951744" },
        { text = "About time.",                                                  sfx = "jl_1934361222363238400" },
        -- very rare, dark family humor (~1%):
        { text = "Checkin' to see if I'm not rotting in some dumpster, like most o' the Welles boys?", sfx = "jl_2008332149470457856", chance = 0.01 },
      },
      choices = {
        { text = "Got a gig. You in?",       to = "gig"     },
        { text = "Just checkin' in on you.", to = "howbeen" },
        { text = "Never mind.",              to = nil       },   -- -> random farewell -> hang up
      },
    },
    howbeen = {
      jackiePool = {
        { text = "Does not get any higher, choom.", sfx = "jl_1660221856871665664" },
        { text = "Eh, you know how it is, can't complain. But we ain't here to shoot the shit about me.", sfx = "jl_1861666308579323904" },
      },
      choices = {
        { text = "Good. Actually - got a gig.", to = "gig" },
        { text = "Glad to hear it.",             to = nil  },   -- -> random farewell -> hang up
      },
    },
    gig = {
      -- His "yeah, I'm in" reply. v0.34b adds the agreement pool from docs/conversations.md.
      -- (Held back "Buen trabajo, V" = praise, and "Yeah, you too" = a reply line - both fit
      -- elsewhere better than agreeing to a gig.)
      jackiePool = {
        { text = "So let's do our thing.",                sfx = "jl_1762127358882361344" },
        { text = "Hold on, V, I'm comin'.",               sfx = "jl_1714251940705820672" },
        { text = "Yeah, OK.",                             sfx = "jl_1883858553243889664" },
        { text = "All right, all right, all right.",      sfx = "jl_1777953524587360256" },
        { text = "Right on, chica.",                      sfx = "jl_1721407637774192672" },
        { text = "You're all right.",                     sfx = "jl_1885197235896905728" },
        { text = "Shit's finally happenin'...",           sfx = "jl_1989698661036924960" },
        { text = "Too late to back out now. Come on, V.", sfx = "jl_1989698664946016264" },
        { text = "And we'd best be quick.",               sfx = "jl_1616247819348959232" },
        { text = "You comin'? Time's precious.",          sfx = "jl_1989698664979570696" },
        { text = "So? You ready?",                        sfx = "jl_1902765821582520320" },
        { text = "Got me right behind you.",              sfx = "jl_1679806464288055296" },
        { text = "Si, si, me acuerdo.",                   sfx = "jl_1989559098138238976" },
        { text = "Anyway, what's goin' on?",              sfx = "jl_1878047791342612480" },
        { text = "We'll snap their necks before they realize.", sfx = "jl_1719792744366325760" },
        -- rare (~5%):
        { text = "Heh, City Hall should be fuckin' thankin' us!", sfx = "jl_1989660111004311552", chance = 0.05 },
      },
      -- v0.34c: TERMINAL node (no `choices`). Once Jackie gives his "I'm in" line the call just
      -- ends and the summon fires - no redundant "Let's do it" click for V. The node-level
      -- `action` is what a choice used to carry. (See branchTick: no-choices node -> auto-end.)
      action = "summon_arrival",
    },
  },
}

-- ---- BIKE RETURN (v0.84 reunion beat) --------------------------------------
-- When the reunion call ends and Jackie walks in (the `reunion_arrival` action), his Arch is removed
-- from V's garage — it's his ride again now that he's alive. One-time, persisted via the game fact
-- below (see jlReturnJackiesBike in init.lua). Also fired by the "Give bike back" debug button.
Config.bikeReturn = {
  enabled    = true,
  bikeRecord = "Vehicle.v_sportbike2_arch_jackie_player",  -- Jackie's Arch (same record the arrival uses)
  fact       = "jackielives_bikeback",
  -- keyItem  = "Items.SomeBikeKey",   -- optional: vanilla 2.x has no bike-"key" item, so leave unset
}

-- ---- BIKE CRUISE (v0.85) ---------------------------------------------------
-- When Jackie is your COMPANION and V rides a BIKE, Jackie summons his Arch and trails behind V
-- (AIVehicleFollowCommand + useKinematic — the AMM bike-follow recipe, proven in JackieVehicleTest).
-- On foot he follows normally; in a CAR, AMM's own companion behaviour seats him as a passenger, so
-- there's nothing to do there. Set enabled=false to turn the whole feature off if it ever misbehaves.
Config.cruise = {
  enabled        = true,
  bikeRecord     = "Vehicle.v_sportbike2_arch_jackie_player",  -- his real Arch (test-confirmed)
  bikeAppearance = "default",
  spawnBehind    = 8.0,     -- metres behind V his Arch spawns when cruise starts
  followDistMin  = 6.0,     -- trail gap (min)
  followDistMax  = 10.0,    -- trail gap (max)
  reissue        = 5.0,     -- re-issue the follow command every N seconds (keeps him locked on)
}

-- ---- BIKE PHYSICS / ANTI-CRASH (v1.41) -------------------------------------
-- "Jackie crashes a lot." Users assume the fix is turning the bike's collisions off. It isn't, and it
-- can't be: the real collider is `entColliderComponent` (branch entIPlacedComponent), which exposes NO
-- scriptable disable. The only runtime `ToggleCollision(Bool)` lives on `entPhysicalMeshComponent`, a
-- VISUAL mesh sub-component that a vehicle chassis does not inherit from. Verified against the CDPR
-- script decompile; see docs/research/bike_cruise_research.md §3.
--
-- The ACTUAL cause is a dedicated engine mechanic, not damage. `vehicleComponent.script`'s
-- `HandleBikeCollisionReaction()` does:
--     knockOffForce = vehicleDataPackage.KnockOffForce() * aiBikeKnockOffModifier   -- NPC drivers only
--     if impactVelocityChange > knockOffForce or IsBeingDragged() then
--         ForceRagdollEvent -> UnmountFromVehicle('Bumped') -> KnockOverBikeEvent -> AIEvent 'NoDriver'
-- i.e. any bump over a force threshold RAGDOLLS the NPC off his bike. Two consequences:
--   * That code path contains NO god-mode check, so invulnerability alone does NOT stop the toppling.
--   * The threshold is a plain TweakDB float we can raise -> he stops being thrown off.
--
-- `aiBikeKnockOffModifier` is GLOBAL (it governs every NPC bike rider in the city), so we only raise it
-- while Jackie is actually on a bike and restore the original the moment he's off. Ref-counted, because
-- the arrival ride-in and the cruise-follow can both want it.
Config.bikePhysics = {
  enabled = true,

  -- Multiplies the NPC knock-off force threshold. 1.0 = vanilla (he gets bumped off by a taxi).
  -- Big number = he stays on the bike. Raise/lower if he still topples or if it feels too glued.
  knockOffModifier = 1000.0,

  -- Make the spawned Arch Invulnerable so a hard hit can't DESTROY it mid-ride (a destroyed bike ends
  -- the follow and strands him). Does not prevent knock-off — that's what knockOffModifier is for.
  godMode = true,

  -- Cruise safety net: if the Arch ends up flipped / on its side, or Jackie gets knocked off it anyway,
  -- right the bike behind V, wake its physics, re-mount him and re-issue the follow.
  rightIfFlipped = true,
  rightCheck     = 1.0,    -- s between upright checks
  rightCooldown  = 4.0,    -- s minimum between two recoveries (never thrash)
  uprightDot     = 0.4,    -- worldUp.z below this = considered toppled
}

-- v0.94b: Config.firstCallTree (the short bike-back fallback call) RETIRED — deleted; git history is
-- the archive. It was never reached in the live flow: reunionCallTree folds in the bike ask, and the
-- Arch is returned on the `reunion_arrival` action. Config.bikeReturn (above) is still used by that
-- arrival + the "Give bike back" debug button, so it stays.

-- ============================================================================
-- REUNION (v0.85) — the retrieval quest's emotional payoff.
-- Flow: read the Rocky Ridge shard -> stage AWAITING_CALL (Jackie has no world
-- presence yet + ALWAYS answers, never "asleep") -> V calls him -> this long call
-- plays -> it ends with Jackie coming over -> he walks in on foot -> the SHORT
-- reunionMeetTree plays face-to-face -> mod fully unlocks (schedule/calls/summon).
-- Text-only lines (like seatedTree) — add `sfx="jl_<id>"` to voice any line later.
-- The bike-back beat is folded in here (the old firstCallTree fallback was retired v0.94b).
-- ============================================================================
Config.reunionCallTree = {
  start = "answer",
  -- v1.56 (Antonia): "no voice lines should fire during the call at all. It sounds weird when it's mostly
  -- subtitle and suddenly a line." Correct — and it was worse than it looked: an unvoiced line still played
  -- the jl_fallback GRUNT, so the call was a stretch of grunting with one real VO clip landing on top of it.
  -- `muteFallback` makes every text-only line GENUINELY SILENT. The ONLY voiced line left in the whole call
  -- is the greeting on `answer` — one short clip, right where a voice is least jarring: the hello.
  muteFallback = true,
  nodes = {
    -- THE ONE VOICED LINE IN THE CALL. Real VO in BOTH tracks — "Chica! Finally!" (female) and a genuine
    -- male clip for "Hermano, finally!" — and it's exactly the right sentiment: he's been sat on this phone
    -- for weeks waiting for it to ring. Short, warm, and it earns the silence that follows.
    answer = {
      jackiePool = {
        { text = "Chica! Finally!", sfx = "jl_2008322358689853440",
          m = { text = "Hermano, finally!", sfx = "jl_jackie_q113_m_1bdefe8b702ef000" } },
      },
      choices = {
        { text = "...Jackie? Is that really your voice?", to = "pickup" },
      },
    },
    pickup = {
      jackiePool = {
        { text = "It's me. It's me, V. Been starin' at this phone for weeks wonderin' if you'd ever ring it." },
      },
      choices = {
        { text = "You son of a bitch. You're ALIVE?",        to = "alive" },
        { text = "Jackie. I buried you. I MOURNED you.",     to = "alive" },
      },
    },
    alive = {
      jackiePool = {
        { text = "Yeah. Yeah, I'm alive, chica. And I'm sorry. Wanted to call a thousand times — Vik wouldn't let me. Said 'Saka'd trace it straight to the both of us.",
          m = { text = "Yeah. Yeah, I'm alive, mano. And I'm sorry. Wanted to call a thousand times — Vik wouldn't let me. Said 'Saka'd trace it straight to the both of us." } },
      },
      choices = {
        { text = "Weeks, Jackie. You let me think you were GONE.",       to = "outrage" },
        { text = "I'm so mad at you I can't—  ...  you're okay?",    to = "outrage" },
      },
    },
    outrage = {
      jackiePool = {
        { text = "I know. I KNOW. Scream at me all you want, chica, I earned every word. C'mon — hit me with it. I can take it better'n a slab in Vik's morgue, heh.",
          m = { text = "I know. I KNOW. Scream at me all you want, mano, I earned every word. C'mon — hit me with it. I can take it better'n a slab in Vik's morgue, heh." } },
      },
      choices = {
        { text = "...You really scared me, choom.", to = "hub" },
      },
    },

    -- ======================= THE HUB (v1.54) ===============================
    -- Was: one long forced chain of "fake" choices that only ever pushed the call forward. Now the call
    -- OPENS UP here, right after V's anger burns off, and she decides what she actually wants to say.
    -- The three topics are `once` — pick one, play it out, and it drops off the list when the branch
    -- walks you back to `hub`, so you can work through all three, in any order, with no repeats.
    -- `final = true` + first position = the yellow "point of no return" plate: it ENDS the call.
    -- The hub line is a small pool so a return trip doesn't replay the same sentence verbatim.
    hub = {
      jackiePool = {
        { text = "So... talk to me, V. Where do we even start, huh?" },
        { text = "Yeah. I'm here. Ain't goin' nowhere this time. What else is on your mind?" },
        { text = "(quiet) Somethin' else, chica? I got all the time in the world for ya.",
          m = { text = "(quiet) Somethin' else, mano? I got nothin' but time out here." } },
      },
      choices = {
        { text = "Enough talkin'. Get over here — I gotta see you with my own eyes.", to = "wrapup", final = true },
        { text = "Your bike. She's still sittin' in my garage, y'know.", to = "bike",   once = "bike" },
        { text = "It's been tough since you were gone, man...",          to = "vlife",  once = "vlife" },
        { text = "So how you been holdin' up out there in the desert?",  to = "desert", once = "desert" },
      },
    },

    -- ---- BRANCH: the Arch --------------------------------------------------
    -- v1.54: V raises it (she's the one who's had it all this time), and she gets a REAL say — hand it
    -- back, or keep it. The `fact` writes the decision straight into the save, because a choice that
    -- routes onward (`to = "hub"`) can't fire an `action`, and reunionMeetTree reads it later, face to face.
    bike = {
      jackiePool = {
        { text = "...My wheels. Dios mío, I didn't wanna ask. C'mon, don't tease me, V — that bike's the one piece o' the old me I got left. Just tell me straight. Is she okay?" },
      },
      -- NO `once` on these two: the hub's bike TOPIC already carries once="bike", and a `once` key is
      -- shared across the whole conversation — reusing it here would filter both rows out the moment the
      -- topic was spent, leaving this node with nothing to pick and the decision never recorded.
      choices = {
        { text = "Relax, hermano. She's safe and sound. Come pick her up.",
          to = "bikeback", fact = { name = "jackielives_bike", value = 1 } },   -- 1 = JL_BIKE_RETURNED
        { text = "About that... I've gotten used to her, Jackie. I'm keepin' her.",
          to = "bikekeep", fact = { name = "jackielives_bike", value = 2 } },   -- 2 = JL_BIKE_KEPT
      },
    },
    bikeback = {
      jackiePool = {
        { text = "Phew... Gracias, V. You got no idea what that means to me. Kept her breathin' for me all this time." },
      },
      choices = {
        { text = "She's yours, Jackie. Always was.", to = "hub" },
      },
    },
    -- The Arch stays with V. He's gutted for exactly one beat — and then he gives it to her, because
    -- that's who he is. No sulking, no penalty: the quest runs on identically from here.
    bikekeep = {
      jackiePool = {
        { text = "...Heh. (a long beat) Nah, nah — you know what? Keep her. Way I see it she kept YOU breathin' while I couldn't. She's earned you, an' you earned her. Just don't let her sit, V. She hates that.",
          m = { text = "...Heh. (a long beat) Nah — you know what? Keep her, hermano. She kept YOU breathin' while I couldn't. Just don't let her sit, V. She hates that." } },
      },
      choices = {
        { text = "...I'll take care of her. Promise.", to = "hub" },
      },
    },

    -- ---- BRANCH: V's last months -------------------------------------------
    -- The old `whatyou`/`deflect` pair, but now it's V who opens the door instead of Jackie prying.
    -- She still can't say the word "Relic" out loud — that stays for the face-to-face (and the lie).
    vlife = {
      jackiePool = {
        { text = "Tough how, V? (beat) Talk to me. Ain't like I got anywhere to be." },
      },
      choices = {
        { text = "Everything went sideways after Konpeki. I'm not... I'm not the same.", to = "vdeflect" },
        { text = "I lost more than you know that night. Damn near lost myself too.",     to = "vdeflect" },
      },
    },
    vdeflect = {
      jackiePool = {
        { text = "Hmm. ...Right. You always did go quiet on the heavy stuff, chica. A'ight. I won't push. For now.",
          m = { text = "Hmm. ...Right. You always did go quiet on the heavy stuff, mano. A'ight. I won't push. For now." } },
      },
      choices = {
        { text = "I'll tell you everything. Just... not over a phone.", to = "hub" },
      },
    },

    -- ---- BRANCH: the desert ------------------------------------------------
    -- The old spine (hiding -> daemon -> quest -> gigs) is exactly the "how've you been out there"
    -- conversation, so that's what it became. It carries the plot (the 'Saka daemon still pinging his
    -- location = why he can't just come home) and it holds BOTH mid-call exits Antonia asked for.
    desert = {
      jackiePool = {
        { text = "(sigh) Honest? Layin' low out here's wearin' me down to nothin', V. Miss the city. The lights, the noise, Mama's cookin'. I wanna come home. But it ain't that simple." },
      },
      choices = {
        { text = "Why not? What's keepin' you stuck out there?", to = "daemon" },
      },
    },
    daemon = {
      jackiePool = {
        { text = "That chip ... whatever got left behind's still runnin'. Some Arasaka security soft - pingin' out where I am like a beacon. That's how 'Saka'd find me — why I gotta stay outta range. Vik tried to cut it. Couldn't." },
      },
      choices = {
        { text = "Then we find someone who CAN. A netrunner, a ripper — anyone.", to = "quest" },
        { text = "We'll get it out of you. I'm not losin' you twice, Jackie.",     to = "quest" },
      },
    },
    -- EXIT #1 (Antonia): the malware's on the table and V has agreed to help -> she can end the call here.
    quest = {
      jackiePool = {
        { text = "You'd really do that? ... 'Course you would. A'ight, chica. We find someone who can pull this thing outta my skull... maybe I get my life back.",
          m = { text = "You'd really do that? ... 'Course you would. A'ight, mano. We find someone who can pull this thing outta my skull... maybe I get my life back." } },
      },
      choices = {
        { text = "We'll get it done. But that's for tomorrow — get over here. Now.", to = "wrapup", final = true },
        { text = "We'll get it done. No worries. I got your back till then.",        to = "gigs" },
      },
    },
    -- EXIT #2 (Antonia): right after he admits he's out of the serious-gig life for good.
    gigs = {
      jackiePool = {
        { text = "(quieter) Gotta be straight with ya, choom. After what happened... I can't be runnin' serious gigs no more. Body won't take it. An' Mama? (chuckle) She'd finish what 'Saka started if I even tried." },
      },
      choices = {
        { text = "Nobody's askin' you to. Now quit talkin' and get over here, hermano.", to = "wrapup", final = true },
        { text = "Good. You've bled enough for this city.",                              to = "hub" },
      },
    },

    -- ---- THE EXIT: wrap the call, send him on his way ----------------------
    -- Every `final` choice above funnels here, so the call always lands the same way no matter which
    -- topics V did or skipped. Nothing here assumes the bike (or anything else) ever came up.
    wrapup = {
      jackiePool = {
        { text = "...Yeah. Yeah, okay. Enough chattin'. Where you at? Nah — don't move, I'm already headed your way. Hang tight, chica.",
          m = { text = "...Yeah. Yeah, okay. Enough chattin'. Where you at? Nah — don't move, I'm already headed your way. Hang tight, mano." } },
      },
      choices = {
        { text = "Okay. I'll be right here. Hurry up.", to = "onmyway" },
      },
    },
    onmyway = {
      -- terminal -> reunion_arrival: Jackie walks in on foot -> first meeting. v1.54: the Arch only goes
      -- back if V promised it (jackielives_bike == 1); the action reads the fact, so this node is neutral.
      -- v1.56: was the VOICED clip "Made it. Almost at your place." — which never made sense as a HANG-UP
      -- line (he hadn't set off yet; the clip was chosen for its audio, and the words were bent to fit it).
      -- Unvoiced now, so it can finally say what this beat actually is: he's hanging up to come to her.
      jackiePool = {
        { text = "I'm already movin', V. Don't you go nowhere. ...I'll see you in a minute, yeah? Been a long time comin'." },
      },
      action = "reunion_arrival",
    },
  },
}

-- The SHORT face-to-face first meeting, played when the walked-in Jackie reaches V.
-- v1.56: same rule as the call — `muteFallback` silences the grunt on every text-only line, and the ONE
-- voiced line is the GREETING. Everything that used to be voiced mid-scene is now text, and rewritten:
-- those subtitles had been bent to match whatever the clip happened to say, which is why they read oddly.
Config.reunionMeetTree = {
  start = "seeya",
  muteFallback = true,
  nodes = {
    -- THE ONE VOICED LINE HERE. A real clip, and it's a greeting — exactly where a voice belongs.
    -- (It also has a real male mirror clip via Config.hermanoLines, so both tracks are voiced.)
    seeya = {
      jackiePool = {
        { text = "Don't come here often, do ya? Heheh. It's good to see you, chica.", sfx = "jl_1661700260668284928" },
      },
      choices = {
        { text = "You've looked better yourself, choom.",     to = "used" },
        { text = "(just look at him a moment) ...It's you.",  to = "used" },
      },
    },
    -- bespoke text-only (no clip fits the hug beat) — full emotional subtitle.
    used = {
      -- BASE = Husbando, `m` = Hermano. v1.54: the Husbando track is warmth, not a courtship — he's glad
      -- to see her and says so. Nothing declared, nothing pined over. That's the whole register now.
      jackiePool = {
        { text = "Yeah, yeah — desert don't do a man's looks any favors. But you? ...Damn. Sight for sore eyes, V. Missed that face more'n I got words for.",
          m = { text = "Yeah, yeah — desert don't do a man's looks any favors. But you, hermano? Damn, you're a sight. Missed that ugly mug o' yours." } },
      },
      -- v1.54: the bike is now OPTIONAL on the call, so the face-to-face has to ask the save what actually
      -- happened before it opens its mouth — otherwise Jackie thanks V for an Arch he never got back.
      -- Same V line, three destinations; `cond` shows exactly one of them. Each predicate is written
      -- defensively (`f and ...`) so that if jlBikeOutcome were ever missing, the neutral route still wins
      -- rather than every row vanishing.
      choices = {
        { text = "We're both still standin'. That's what counts.", to = "drivehome",
          cond = function() local f = jlBikeOutcome; return (f ~= nil) and f() == 1 end },   -- 1 = she promised it back
        { text = "We're both still standin'. That's what counts.", to = "keptride",
          cond = function() local f = jlBikeOutcome; return (f ~= nil) and f() == 2 end },   -- 2 = she's keeping it
        { text = "We're both still standin'. That's what counts.", to = "leave",
          cond = function() local f = jlBikeOutcome; return (f == nil) or f() == 0 end },    -- 0 = never came up
      },
    },
    -- v1.56: was the VOICED clip "Aah, savin' my ass, V, thank you. How about I drive you home, eh?" — the
    -- words were picked for the audio, and "savin' my ass" is a strange thing to say about a KEPT BIKE.
    -- Unvoiced now, so it can be the beat it actually is: he's just realised she never sold the Arch.
    drivehome = {
      jackiePool = {
        { text = "...Hold up. My bike. You still got her? All this time, you kept her?" },
      },
      choices = {
        { text = "She's in my garage, Jackie. Waiting for you. Here — your keys.", to = "bikejoy" },
      },
    },
    -- v1.54: V told him on the call she's keeping the Arch. He's already made his peace with it — so he
    -- turns it into a joke and makes HER drive. Text-only (no clip fits); ends at the same `leave` beat.
    keptride = {
      jackiePool = {
        { text = "So you really are keepin' her, huh. (laughs) A'ight, a'ight — then YOU'RE drivin', chica. C'mon. Show me she's been in good hands.",
          m = { text = "So you really are keepin' her, huh. (laughs) A'ight — then YOU'RE drivin', hermano. C'mon. Show me she's been in good hands." } },
      },
      choices = {
        { text = "Get on, Jackie. Let's go home.", to = "leave" },
      },
    },
    -- v0.94b: MUTE (text-only) — the Miguel VO clip didn't fit here. Bespoke subtitle: he's just
    -- floored his bike was kept safe. Add `sfx = "jl_<id>"` later if a fitting clip turns up.
    bikejoy = {
      jackiePool = {
        { text = "You kept her runnin' for me. All this time... Damn, V. That's the last piece o' the old me, right there." },
      },
      choices = {
        { text = "Let's go, hermano, and you can take her for a spin.", to = "leave" },
      },
    },
    leave = {
      -- terminal -> reunion_complete: unlock the whole mod (schedule + calls + summon).
      -- v1.56: was the VOICED clip "...I'm dyin' for some fresh air" — a line about wanting to get OUTSIDE,
      -- which is a strange note to close the reunion on (he's spent months in an empty desert). Unvoiced now,
      -- so it can land the moment properly: he's home, and he's not going anywhere again.
      jackiePool = {
        { text = "C'mon, V. Let's go home. ...And hey — no more funerals. Not for a good long while, yeah?",
          m = { text = "C'mon, hermano. Let's go home. ...And hey — no more funerals. Not for a good long while, yeah?" } },
      },
      action = "reunion_complete",
    },
  },
}

-- ---- BLAZE finale conversation (v1.10) ------------------------------------
-- Plays at the Blaze finale, once V wakes at the destination and Jackie (normal outfit) is standing
-- facing her. Subtitle-only EXCEPT Jackie's closing "So what now?" (real voiced clip). Same tree engine
-- as the reunion (Branch.start); V lines are silent text choices. Terminal action "blaze_finale_complete".
-- Antonia's script (docs/jackie_V_final_convo.txt) + her notes 2026-07-09: LONGER preamble (catch a
-- breath / pause / "shame nobody'll know it was us") BEFORE the case comes up; the dawning realization;
-- then the destroyed-chip reveal; V gets 3 options (ONE angry), forking to Jackie's mad/easy reply.
Config.blazeFinaleTree = {
  start = "madeit",
  nodes = {
    madeit = {
      jackiePool = { { text = "Híjole... we made it. We actually made it. Can't believe it, V." } },
      choices = {
        { text = "(catch your breath) ...Yeah. We did.", to = "alive" },
      },
    },
    alive = {
      jackiePool = { { text = "We're alive, chica. Both of us." } },
      choices = {
        { text = "Barely caught a breath since Konpeki. ...Feels good to just stop a second.", to = "pause" },
      },
    },
    -- the pause beat + "shame nobody'll know it was us" (Antonia's verbal note, this turn).
    pause = {
      jackiePool = { { text = "Heh... yeah. It does. ...Shame nobody's ever gonna know it was us up there." } },
      choices = {
        { text = "By the way -- where'd you store the case?", to = "case_q" },
      },
    },
    case_q = {
      jackiePool = { { text = "Well..." } },
      choices = {
        { text = "...Jackie?", to = "deflect" },
      },
    },
    -- the dawning realization: he deflects once more, then V snaps to it.
    deflect = {
      jackiePool = { { text = "I had it. Right in my hands, V, I swear I did..." } },
      choices = {
        { text = "Jackie! The biochip -- the fucking case with the biochip, where is it?!", to = "reveal" },
      },
    },
    -- reveal wording = Antonia's file (docs/jackie_V_final_convo.txt).
    reveal = {
      jackiePool = { { text = "I tried to hold onto it, I swear. Smasher -- that hijo de puta... Case took a round, cracked wide open. Chip's slag. So I dropped it. ...I'm sorry, V. I really am." } },
      -- 3 options, ONE angry (-> mad); the other two let-it-go (-> easy). Wording from Antonia's file.
      choices = {
        { text = "Fuck! That was our ticket Jackie! Everything we worked for!",            to = "mad"  },
        { text = "Honestly? Thing probably woulda been more trouble than it was worth.",    to = "easy" },
        { text = "We're both breathing, cabrón. That's the only score that matters.",       to = "easy" },
      },
    },
    mad = {
      jackiePool = { { text = "Yeah... I know. Chinga'o. But hey -- you're still here to be pissed about it, right?" } },
      choices = {
        { text = "(let out a breath) ...Guess I am.", to = "legend" },
      },
    },
    easy = {
      jackiePool = { { text = "...Yeah. Maybe you're right. Corpo tech like that only ever buys you a shorter life." } },
      choices = {
        { text = "Damn right.", to = "legend" },
      },
    },
    -- Antonia's file line: pride in the feat (distinct from the earlier "shame nobody'll KNOW it was us").
    legend = {
      jackiePool = { { text = "You and me. Walked outta Konpeki Plaza. Nobody's ever gonna believe it." } },
      choices = {
        { text = "Let 'em not believe it.", to = "whatnow" },
      },
    },
    whatnow = {
      -- SUBTITLE-ONLY (Antonia: the voiced 'So what now?' clip was bad — use her literal line, no audio).
      jackiePool = { { text = "Okay soo... What's next?" } },
      choices = {
        { text = "Whatever we want, hermano. For once, nobody's writing our story but us.", to = "done" },
      },
    },
    done = {
      -- terminal: Jackie's last beat, then the convo ends (he stays your companion). Action is a hook.
      jackiePool = { { text = "...Heh. I like the sound o' that. C'mon, then. Night City ain't gonna know what hit it." } },
      action = "blaze_finale_complete",
    },
  },
}

-- ---- free-roam wander (v0.35) ---------------------------------------------
-- While idle-spawned at a scheduled location, Jackie walks between that location's
-- `waypoints`: stands/sits/leans at one for a random dwell, then strolls to a RANDOM
-- other point (never an immediate repeat, so he won't pace back-and-forth), and repeats.
-- A location with a single waypoint just plants him there. He stays a PASSIVE NPC the
-- whole time (no follower role) — wandering Jackie is not a companion.
Config.wander = {
  enabled         = true,
  movement        = "Walk",   -- "Walk" | "Run" — how he strolls between points
  arriveDist      = 1.5,      -- metres from a waypoint that counts as "arrived"
  dwellMin        = 30.0,     -- seconds: shortest stand/sit at a point (per-wp override: dwell = {a,b})
  dwellMax        = 90.0,     -- seconds: longest (v0.40: middle ground between 15/45 and 45/150)
  repath          = 2.5,      -- re-issue the move every this many seconds while walking
  arriveTimeout   = 30.0,     -- give up walking to a point after this long, dwell anyway
  faceYawOnArrive = true,     -- snap onto the waypoint's exact spot + yaw on arrival (lean/sit framing)
}

-- ---- sit / lean poses (v0.39) ---------------------------------------------
-- Real sit/lean ANIMATIONS, via AMM's own workspot system (the exact path AMM's Poses tab uses:
-- Game.GetWorkspotSystem():PlayInDeviceSimple + SendJumpToAnimEnt). When Jackie dwells at a
-- waypoint whose pose is "sit" or "lean", we call AMM.Poses:PlayAnimationOnTarget(target, anim)
-- with the records below; when he leaves the spot we StopInDevice so he gets up. All guarded —
-- if AMM's Poses module isn't reachable it silently falls back to just standing on the spot.
-- anim names are AMM `workspots` rows (rig "Man Average", comp "amm_workspot_base"). Swap the
-- `name` for any other from AMM's Poses tab to change the look (e.g. sit_chair_table__2h_cup__02).
-- IMPORTANT: AMM's sit/lean are FREESTANDING anims (invisible chair) rooted at the waypoint spot —
-- they do NOT snap onto a real chair. So (a) we DEFER the play by `delay` s so the snap-teleport
-- lands first (else the pose spawns where he WAS = floating), and (b) you align him to a real chair
-- by tuning the waypoint: re-capture standing where his SEATED body goes, and/or set a per-waypoint
-- `poseOffset = { x=, y=, z= }` (world-space metres) to nudge him onto the seat (z down = lower him).
-- A waypoint can override the anim with `poseAnim = "<name>"` — e.g. most of Jackie's chairs are
-- BARSTOOLS (default below), but Misty's is a deep low chair, so that waypoint sets the low-chair anim.
Config.poses = {
  enabled = true,
  delay   = 0.5,    -- seconds after the snap-teleport before playing the pose (fixes the float race)
  ent     = "base\\amm_workspots\\entity\\workspot_anim.ent",
  comp    = "amm_workspot_base",
  rig     = "Man Average",
  sit     = "sit_barstool__2h_on_lap__01",          -- DEFAULT = barstool (most of his chairs)
  sitChair= "sit_chair__2h_on_lap__01",             -- low/deep chair (Misty's) — used via poseAnim
  lean    = "stand_wall_lean180__2h_on_wall__01",
}

-- ---- DIALOGUE PICKER placement (v1.42) -------------------------------------
-- The choice box used to sit at a fixed 620x240 px, horizontally centred then nudged 150 px LEFT, at
-- 46% screen height — i.e. middle-left-ish, and it drifted with resolution (on 4K it read as a tiny box
-- floating in the upper-left quadrant, because the pixel size never changed while the screen doubled).
--
-- Now: everything is expressed RELATIVE to the display. The box is uniformly scaled by `sh / refH`, then
-- horizontally CENTRED and dropped into the lower band of the screen. Because the box scales with the
-- screen, it occupies the same fraction of it at 1080p, 1440p, 4K and on ultrawides (where centring uses
-- the real width, so it stays under the crosshair rather than drifting left).
--
-- v1.47 (Antonia): the lower-fifth placement OVERLAPPED THE NATIVE SUBTITLE LINE, which lives at the bottom
-- of the screen. So the box top is positioned by `topFrac` instead.
--
-- ⚠️ v1.51: `topFrac` is measured DOWN FROM THE TOP of the screen. v1.47 set it to 0.36 by reading Antonia's
-- "36%" as 36% from the top — which put the box just ABOVE centre ("VERY high"). She meant 36% UP FROM THE
-- BOTTOM, so the correct value is 1 - 0.36 = 0.64. Since the box is baseH/refH ≈ 22% of screen height, it now
-- spans 64%..86%: lower half, clear of the subtitle band. If you retune this, remember the axis points DOWN —
-- a BIGGER topFrac means LOWER on screen. (History: lower-fifth ≈ 0.78 was too low and hit the subtitles;
-- 0.36 was far too high; 0.64 is the value Antonia picked from a mock-up.)
-- `bottomMargin` stays purely a safety clamp so the box can never run off the bottom at an extreme aspect
-- ratio / scale clamp; it should not bind at 0.64.
Config.picker = {
  refH        = 1080.0,  -- the resolution the base sizes below were designed at
  baseW       = 620.0,   -- box width  @ refH
  baseH       = 240.0,   -- box height @ refH (must fit the tallest choice list, unscrollable)
  baseFont    = 1.45,    -- ImGui font scale @ refH
  nameW       = 128.0,   -- "JACKIE" name plate @ refH
  nameH       = 34.0,
  topFrac     = 0.64,    -- TOP EDGE of the box, as a fraction of screen height DOWN FROM THE TOP (bigger = lower)
  bottomMargin= 0.02,    -- safety clamp only: keep at least this fraction of the screen below the box
  minScale    = 0.8,     -- clamp so a tiny window can't make it unreadable...
  maxScale    = 3.0,     -- ...or a huge one make it cartoonish
  xOffset     = 0.0,     -- px @ refH: nudge horizontally if you want it off-centre (+right / -left)
}

-- ---- LOOK-AT / head tracking (v1.41) ---------------------------------------
-- As a COMPANION Jackie already head-tracks V, because sendWalkToPlayer's AIFollowTargetCommand carries
-- `lookAtTarget = Game.GetPlayer()`. A venue Jackie has no follow command, so he was frozen at whatever
-- yaw the seat/waypoint baked in — staring through you.
--
-- The engine's own head/eye tracking is `entLookAtAddEvent` (REDscript `LookAtAddEvent`), an ANIMATION
-- GRAPH OVERLAY. Two properties make it exactly what we want:
--   * `SetEntityTarget(player, ...)` makes the engine follow the live entity itself — we queue it ONCE
--     and it tracks V as she walks around. No per-frame teleport, no yaw math, no jitter.
--   * It layers on top of the base animation, so it composes with the AMM sit workspot. It turns his
--     HEAD, not his body, so it can't eject him from the barstool.
-- Vanilla uses precisely this in reactionComponent.script (bodyPart 'Eyes', slot 'pla_default_tgt',
-- soft/hard/back limits 360/270/210). See docs/research/lookat_research.md.
--
-- ⚠️ The CET-Lua marshalling of this event is UNVERIFIED (no shipped Lua mod constructs it). jlLookAtStart
-- tries every construction form and logs which one took; if all fail it degrades to "no look-at" and
-- Jackie behaves exactly as he did before. It can't break him.
Config.lookAt = {
  enabled    = true,
  range      = 12.0,   -- m: start tracking V once she's this close
  dropRange  = 15.0,   -- m: stop tracking beyond this (hysteresis, so it can't flicker at the boundary)
  check      = 0.5,    -- s between distance checks (the tracking itself is engine-side, this is just arm/disarm)
  bodyPart   = "Eyes", -- CONFIRMED literal used by vanilla reactionComponent ('LeftHand' is the only other confirmed one)
  targetSlot = "pla_default_tgt",  -- the look-at slot on the PLAYER that vanilla aims at

  -- Wide limits: a seated pose already twists his head, so a narrow cone would hit the hard limit and
  -- he'd stop short of actually facing V. These mirror vanilla's 360/270/210 soft/hard/back degrees.
  softLimit = "Wide", hardLimit = "Wide", backLimit = "Normal", distLimit = "None",
}

-- ---- collision ownership (v0.44) ------------------------------------------
-- NPCs get shoved out of / blocked from chairs by collision. We drop NPCPuppet collision around
-- seating. Two INDEPENDENT owners (they used to fight via shared pose helpers — now separated):
--   • IDLE Jackie  -> Config.idleNoCollision (below). Applied once at placement; off his whole stay.
--   • DINNER Jackie -> hard-wired in dinnerTick (drop on `seating`, restore when he stands).
-- COMPANION Jackie always collides (promoteToCompanion forces it on). See init.lua header map.
--
-- MASTER switch: keep idle Jackie collision-free from the moment he's placed, so chairs/stalls can't
-- block or shove him. Trade-off: V can walk through idle Jackie. Flip live from the mod window
-- ("Idle Jackie: collisions OFF"). Companion/dinner Jackie unaffected.
Config.idleNoCollision = true

-- ---- locations ------------------------------------------------------------
-- Capture coords in-game with the "Capture current position" button, then paste the
-- printed line into the matching entry below. Each location has an ANCHOR (`pos`/`yaw` —
-- where he first appears / falls back to) and an optional `waypoints` list he free-roams
-- between. Per-waypoint: pos = {x,y,z}, yaw = deg, pose = "stand"|"sit"|"lean",
-- dwell = {min,max} (optional, overrides Config.wander.dwell*).
-- NOTE: pose "sit"/"lean" currently just plants him on the spot facing `yaw` — a real
-- sit/lean WORKSPOT animation is a TODO, so the pose tags are forward-looking data.
-- See docs/captured_positions.md for the human-readable tables.
--
-- OUTFITS (v0.39): each location carries an `appearance` — Jackie's REAL AMM appearance name.
-- ⚠️ v1.43: these NEVER ACTUALLY APPLIED until now. ammSpawn passed AMM the appearance as a table
-- (`{ app = name }`) where a plain string was required, so every spawn silently fell back to his record
-- default. It went unnoticed because 3 of the 7 venues want `jackie_welles_default` anyway. Fixed in
-- init.lua's ammSpawn; expect misty/afterlife/redwood/ginger/lizzies to CHANGE LOOK now.
-- All names below verified against AMM's shipped appearance DB for Character.Jackie. Wardrobe mapping:
--   jackie_welles_default               -> noodle, coyote, test, and the summon/arrival fallback
--   jackie_welles_default_collar_down   -> misty, afterlife, redwood
--   jackie_welles__q000_lizzies_club_no_jacket -> ginger (Ginger Panda) + lizzies (Lizzie's Bar)
--   jackie_welles__q005_suit            -> reserved for a future "date" day (not used at a location yet)
-- The full 17 on Character.Jackie (note: quest-tagged ones take a DOUBLE underscore, the rest single):
--   default · default_collar_down · default_no_machete · __q000_lizzies_club_no_jacket ·
--   __q000_lizzies_club_no_machete · __q005_suit · __q005_suit_bleeding · __q005_suit_dirty ·
--   __q005_suit_wounded · valentino · valentino_beaten_up · valentino_beaten_up_alt ·
--   valentino_collar_down · wounded · wounded_bleeding · naked · naked_erect
Config.defaultAppearance = "jackie_welles_default"   -- summon/arrival + any location with no `appearance`
Config.locations = {
  -- captured 2026-06-16 (Antonia). sitNearest kept for the future chair-sit feature.
  noodle = {
    name = "Noodle bar", appearance = "jackie_welles_default", pos = { -1439.472, 1259.021, 23.090 }, yaw = -87.1, sitNearest = true,
    exitWaypoint = { pos = { -1440.553, 1258.332, 23.099 }, yaw = -108.3 },   -- outside the stall (may not reach if unloaded)
    waypoints = {   -- v0.45: ONE seat = the MIDDLE stool. (Two stools made him fidget/hop between them.)
      { pos = { -1439.472, 1259.021, 23.090 }, yaw = -87.1, pose = "sit" },   -- MIDDLE stool
      -- DEPRECATED right stool (kept for reference): pos = { -1440.477, 1258.164, 23.090 }, yaw = -87.1
    },
  },

  -- Misty REPLACES Vik/Vic as a destination (Antonia). Re-captured 2026-06-17.
  -- Her chair is a DEEP/low chair (not a stool) -> that sit waypoint overrides the barstool anim.
  misty = {
    name = "Misty's Esoterica", appearance = "jackie_welles_default_collar_down", pos = { -1541.777, 1196.792, 15.905 }, yaw = 86.6,
    exitWaypoint = { pos = { -1547.112, 1185.049, 16.493 }, yaw = -159.8 },   -- outside (may not reach if unloaded)
    waypoints = {
      { pos = { -1541.777, 1196.792, 15.905 }, yaw = 86.6, pose = "stand" },  -- anchor
      { pos = { -1547.493, 1196.449, 16.260 }, yaw = 61.7, pose = "stand" },  -- near small cats
      { pos = { -1541.289, 1194.016, 16.600 }, yaw = 46.1, pose = "sit", poseAnim = "sit_chair__2h_on_lap__01" },  -- deep chair
    },
  },

  -- El Coyote Cojo (Mama Welles' bar). Captured 2026-06-17.
  -- exitWaypoint: the spot inside Coyote where he heads to "go home / to bed" before despawning
  -- (Antonia's chosen final despawn point). Also Jackie's canonical home-exit for asleep/home blocks.
  coyote = {
    name = "El Coyote Cojo", appearance = "jackie_welles_default", pos = { -1262.463, -1002.345, 12.037 }, yaw = -50.9,
    exitWaypoint = { pos = { -1247.138, -985.136, 16.027 }, yaw = -77.3 },   -- final despawn spot -> home/bed
    waypoints = {
      { pos = { -1262.463, -1002.345, 12.037 }, yaw = -50.9, pose = "lean"  },  -- right of bar
      { pos = { -1243.806,  -993.222, 12.505 }, yaw = -79.2, pose = "stand" },  -- arcade station
      { pos = { -1257.939,  -987.950, 16.038 }, yaw =  64.1, pose = "sit"   },  -- upstairs table
      { pos = { -1267.961,  -990.652, 16.027 }, yaw = 175.8, pose = "stand" },  -- upstairs vending
      { pos = { -1263.294,  -996.467, 16.017 }, yaw = -80.0, pose = "lean"  },  -- upstairs railing
      { pos = { -1262.646,  -984.029, 12.037 }, yaw =   6.5, pose = "lean"  },  -- outside door
    },
  },

  -- Afterlife (merc legends bar, night). Captured 2026-06-17.
  afterlife = {
    name = "Afterlife", appearance = "jackie_welles_default_collar_down", pos = { -1457.063, 1018.598, 16.524 }, yaw = -96.9,
    exitWaypoint = { pos = { -1471.229, 1038.869, 22.661 }, yaw = 167.6 },   -- toward the exit (end of shift)
    waypoints = {
      { pos = { -1457.063, 1018.598, 16.524 }, yaw =  -96.9, pose = "lean"  },  -- near entrance
      { pos = { -1444.870, 1034.471, 16.923 }, yaw =   54.9, pose = "stand" },  -- alcove, watching
      { pos = { -1454.586, 1009.834, 16.500 }, yaw =   65.3, pose = "stand" },  -- watching dancers
      { pos = { -1449.437, 1012.129, 17.357 }, yaw = -168.3, pose = "sit"   },  -- bar (right side, barstool)
    },
  },

  -- Ginger Panda + Redwood: in the active2/active3 day schedules. Ginger Panda waypoints 2-7
  -- are the "Any Austin" walk-in-circles easter egg (ordered-loop mode is a TODO; random-roam now).
  ginger = {
    name = "Ginger Panda", appearance = "jackie_welles__q000_lizzies_club_no_jacket", pos = { -485.426, 576.939, 31.302 }, yaw = -17.1,
    waypoints = {
      { pos = { -485.426, 576.939, 31.302 }, yaw =  -17.1, pose = "sit", dwell = { 60, 120 } },  -- bar
      { pos = { -491.638, 592.985, 31.802 }, yaw = -113.3, pose = "stand" },
      { pos = { -483.382, 588.253, 31.802 }, yaw = -153.4, pose = "stand" },
      { pos = { -475.878, 581.170, 31.802 }, yaw = -174.1, pose = "stand" },
      { pos = { -485.072, 570.963, 31.802 }, yaw =  113.3, pose = "stand" },
      { pos = { -494.347, 576.980, 31.802 }, yaw =  -82.7, pose = "stand" },
      { pos = { -496.151, 584.078, 31.802 }, yaw =  -36.3, pose = "stand" },
    },
  },

  redwood = {
    name = "Redwood Market", appearance = "jackie_welles_default_collar_down", pos = { -402.802, 710.778, 123.000 }, yaw = 108.1,
    waypoints = {
      { pos = { -402.802, 710.778, 123.000 }, yaw = 108.1, pose = "lean"  },  -- upstairs view
      { pos = { -422.418, 700.581, 114.999 }, yaw =  58.9, pose = "stand" },  -- bridge
      { pos = { -448.024, 685.905, 115.028 }, yaw = 106.2, pose = "stand" },  -- coffee vendor
      { pos = { -431.550, 669.948, 115.010 }, yaw = -33.5, pose = "stand" },  -- noodle place
    },
  },

  -- Lizzie's Bar (Mox club). Captured 2026-06-17. NOTE: closed before 21:00 -> only scheduled
  -- in active1's 21:00-23:30 slot. exitWaypoint = the outside spot (his departure point).
  lizzies = {
    name = "Lizzie's Bar", appearance = "jackie_welles__q000_lizzies_club_no_jacket", pos = { -1194.874, 1561.692, 22.915 }, yaw = -85.6,
    exitWaypoint = { pos = { -1204.007, 1565.463, 22.920 }, yaw = 10.1 },   -- outside -> departure
    waypoints = {
      { pos = { -1194.874, 1561.692, 22.915 }, yaw = -85.6, pose = "stand" },  -- at entrance
      { pos = { -1174.427, 1572.135, 23.115 }, yaw = -68.5, pose = "sit"   },  -- rear bar
    },
  },

  -- captured 2026-06-16 for the native-box test (your standing spot in the test save):
  test = { name = "Test spot", pos = { -854.737, 1833.329, 36.207 }, yaw = 44.4 },

  -- SECRET nap spot (v0.41 easter egg): during his sleep window he has a small chance to be here
  -- instead, leaning. Wired by Config.secret below. appearance = default (he's "off duty").
  secret = {
    name = "(secret nap spot)", appearance = "jackie_welles_default", pos = { -1470.154, 1201.503, 19.084 }, yaw = -41.9,
    waypoints = {
      { pos = { -1470.154, 1201.503, 19.084 }, yaw = -41.9, pose = "lean" },
    },
  },
}

-- ---- secret sleeping-hours cameo (v0.41) ----------------------------------
-- While the schedule says he's ASLEEP (startHour..endHour, the unavailable sleep window), roll ONCE
-- per night: with `chance` he instead shows up at Config.locations[locationKey] (leaning). If the
-- roll misses, he's truly gone that night. Re-rolls each new night.
Config.secret = {
  locationKey = "secret",
  chance      = 0.20,    -- 20% per night
  startHour   = 2,       -- phone-unavailable window = 02:00–06:00 (4h/night; reduced from 0–6)
  endHour     = 6,
}

-- ---- approach cameo (v1.3) -------------------------------------------------
-- Jackie only ever runs 3-4 of his 7 venues on any given day, so V rarely bumps into him. This
-- raises the odds: whenever V gets within `radius` of ANY venue during his active hours
-- (06:00-00:00), roll ONCE to force his schedule to that venue for the rest of the in-game day
-- (he shows up where V actually is). The FIRST appearance of the day rolls at `premiumChance`; each
-- new venue-approach keeps rolling at that rate UNTIL one lands, after which every roll drops to
-- `repeatChance`. The noodle bar is ALWAYS `noodleChance` (V passes it far too often to earn the
-- premium). Each venue only re-rolls after V has left its radius and returned (no per-tick spam).
-- Resets every in-game day. Sleep hours are left to the secret-nap cameo above.
Config.approach = {
  enabled       = true,
  radius        = 20.0,   -- metres: V this close to a venue triggers one roll
  premiumChance = 0.35,   -- first daily appearance (non-noodle) — the "premium" shot
  repeatChance  = 0.10,   -- after he's appeared once via this mechanic today
  noodleChance  = 0.10,   -- noodle bar is ALWAYS this (V passes it constantly)
  venues = { "noodle", "misty", "coyote", "afterlife", "ginger", "redwood", "lizzies" },
}

-- ---- daily schedules (v0.37a: 5 day-types, shuffled, 3 stops/day) ----------
-- One state per time-of-day block. startHour/endHour are FRACTIONAL hours (e.g. 23.5 = 23:30),
-- so half-hour blocks work. state = "at_location" (needs locationKey) or "unavailable".
--
-- DESIGN:
--   * BEDTIME = MIDNIGHT. Sleep is 00:00-06:00, so the day-type boundary (midnight) lands while
--     he's asleep — no activity block ever straddles the rollover. Activities run 06:00-00:00.
--   * Each active day = 3-4 MAIN stops (long, ~3-6h each) totalling ~14h PRESENT (only 4h home +
--     6h sleep). Long settled stays, varied across the day. (quiet/gone are the exceptions.)
--   * HE ALWAYS RETURNS TO EL COYOTE before bed, then heads "upstairs" to sleep (that upstairs
--     spot is his despawn/home point — V1.0 transitions). On most days this is the 23:30-00:00
--     wind-down; on active3/quiet his evening IS Coyote, so it runs straight to midnight.
--     EXCEPTION: the `gone` day (he's out of town).
--   * 5 DAY-TYPES in a SHUFFLE BAG (Config.dayBag): each in-game day pops the next, reshuffling
--     when empty — every 5-day cycle uses each type once (no skips) in random order. All seven
--     venues appear across the active days: noodle/misty/lizzies (A1), redwood/ginger/afterlife
--     (A2), noodle/misty/afterlife/coyote (A3). (Lizzie's opens 21:00 -> only its late A1 slot.)
Config.daySchedules = {
  -- ACTIVE 1 — Noodle (5h) + Misty's (6h) + Lizzie's (2.5h, opens 21:00) + Coyote wind-down
  active1 = {
    { startHour = 0,    endHour = 6,    state = "unavailable"                            },  -- asleep (6h)
    { startHour = 6,    endHour = 8,    state = "unavailable"                            },  -- home (2h)
    { startHour = 8,    endHour = 13,   state = "at_location", locationKey = "noodle"    },  -- 5h
    { startHour = 13,   endHour = 15,   state = "unavailable"                            },  -- home (2h)
    { startHour = 15,   endHour = 21,   state = "at_location", locationKey = "misty"     },  -- 6h
    { startHour = 21,   endHour = 23.5, state = "at_location", locationKey = "lizzies"   },  -- 2.5h (Lizzie's opens 21:00)
    { startHour = 23.5, endHour = 24,   state = "at_location", locationKey = "coyote"    },  -- wind-down 0.5h
  },
  -- ACTIVE 2 — Redwood (5h) + Ginger Panda (4h) + Afterlife evening (4.5h) + Coyote wind-down
  active2 = {
    { startHour = 0,    endHour = 6,    state = "unavailable"                            },  -- asleep (6h)
    { startHour = 6,    endHour = 8,    state = "unavailable"                            },  -- home (2h)
    { startHour = 8,    endHour = 13,   state = "at_location", locationKey = "redwood"   },  -- 5h
    { startHour = 13,   endHour = 17,   state = "at_location", locationKey = "ginger"    },  -- 4h
    { startHour = 17,   endHour = 19,   state = "unavailable"                            },  -- home (2h)
    { startHour = 19,   endHour = 23.5, state = "at_location", locationKey = "afterlife" },  -- 4.5h (evening)
    { startHour = 23.5, endHour = 24,   state = "at_location", locationKey = "coyote"    },  -- wind-down 0.5h
  },
  -- ACTIVE 3 — busy: Noodle (4h) + Misty's (3h) + Afterlife (3h) + El Coyote evening -> bed (4h)
  active3 = {
    { startHour = 0,  endHour = 6,  state = "unavailable"                            },  -- asleep (6h)
    { startHour = 6,  endHour = 8,  state = "unavailable"                            },  -- home (2h)
    { startHour = 8,  endHour = 12, state = "at_location", locationKey = "noodle"    },  -- 4h
    { startHour = 12, endHour = 15, state = "at_location", locationKey = "misty"     },  -- 3h
    { startHour = 15, endHour = 17, state = "unavailable"                            },  -- home (2h)
    { startHour = 17, endHour = 20, state = "at_location", locationKey = "afterlife" },  -- 3h
    { startHour = 20, endHour = 24, state = "at_location", locationKey = "coyote"    },  -- 4h -> bed
  },
  -- QUIET — low-key: Misty's (4h) + El Coyote (3h), otherwise home
  quiet = {
    { startHour = 0,  endHour = 6,  state = "unavailable"                            },  -- asleep (6h)
    { startHour = 6,  endHour = 14, state = "unavailable"                            },  -- home (8h)
    { startHour = 14, endHour = 18, state = "at_location", locationKey = "misty"     },  -- 4h
    { startHour = 18, endHour = 21, state = "unavailable"                            },  -- home (3h)
    { startHour = 21, endHour = 24, state = "at_location", locationKey = "coyote"    },  -- 3h -> bed
  },
  -- GONE — out of town; never appears all day (the one day with no Coyote return)
  gone = {
    { startHour = 0, endHour = 24, state = "unavailable" },
  },
}

-- The shuffle bag. init.lua plays these in a random order, one per in-game day, each exactly
-- once per cycle, then reshuffles. Add/remove day-types here to change the rotation.
Config.dayBag = { "active1", "active2", "active3", "quiet", "gone" }

-- Fallback day-type used if the day system can't read the game day for some reason.
Config.fallbackDay = "active1"

-- ---- location transitions (V1.0 — config in place; state machine NOT wired yet) ----------
-- A real cross-map walk is impossible (NPC navmesh is local + he's unloaded out of streaming
-- range), so transitions are faked: when his block changes he DEPARTS on foot to a venue exit
-- and despawns once out of range; after `transitRealSeconds` he is "in transit" and won't
-- spawn; then he ARRIVES at the new venue either on foot from ~`arriveDistanceM` out (reusing
-- the holocall walk-in) or by teleport-to-spot. Going home/asleep, he heads to El Coyote's
-- upstairs exit and despawns there. These knobs are READ by the V1.0 machine (to be built).
Config.transitions = {
  transitRealSeconds = 50,    -- REAL seconds he's "en route" after a block change (won't spawn)
  arriveOnFoot       = true,  -- true = spawn ~arriveDistanceM from the venue + walk in; false = teleport to spot
  arriveDistanceM    = 60.0,  -- metres from the venue anchor he spawns at for the walk-in
  -- WALK-AWAY (v0.38, BUILT): when his block ends and he's spawned + you're nearby, he walks to the
  -- venue's exit (loc.exitWaypoint -> e.g. Coyote upstairs / Lizzie's outside; else just away from V)
  -- and despawns once he reaches it, leaves your range, or `leaveTimeout` passes.
  departOnFoot       = true,
  leaveTimeout       = 20.0,  -- seconds: despawn anyway if he can't reach the exit
  leaveReachDist     = 2.5,   -- metres from the exit point that counts as "left"
  exitReach          = 18.0,  -- metres he walks away from V at venues with no exitWaypoint
  -- RETURN-TO-POST (v0.40): when you DISMISS companion Jackie and the schedule currently wants him
  -- at a venue within this many metres, he walks BACK to it and re-joins the idle cycle instead of
  -- despawning. Farther away (or not scheduled anywhere) -> the normal walk-away-and-despawn.
  returnRadius       = 100.0,
}

-- ---- main-quest ban -------------------------------------------------------
-- When V is on a main quest, summoning is declined. MVP: detection is stubbed;
-- use the "Force main-quest active" checkbox in the UI to test the decline flow.
-- We'll fill this blocklist with real main-quest IDs once we read them in-game.
Config.mainQuestBlocklist = {
  -- "mq001", "mq005", ...
}
Config.declineLine = "V: Not draggin' Jackie into this mess. Not after everything he went through."

-- v0.93: the SAME refusal, but written for the blue on-screen NOTICE band (top-left objective-style
-- notifications), so a call/summon that no-ops during a main quest tells the player WHY instead of
-- looking broken. Kept short so it fits the notice band; declineLine stays V's spoken/status line.
Config.mainQuestBlockNotice = "Can't call Jackie during a main mission — not draggin' him into this."

return Config
