-- Jackie Lives — configuration
-- Antonia edits THIS file. Coordinates are captured in-game (see README).

local Config = {}

-- Mod version. Bump on every deploy; deploy.ps1 prints it and init.lua logs it on load.
Config.version = "0.84"

-- ---- master toggles -------------------------------------------------------
-- DEBUG: when true, the mod hooks native phone/holocall methods at load and prints a
-- [JackieLives PROBE] line whenever one fires. Open your phone + call Jackie, then read the
-- CET console to see which methods drive the call (tells us if a native hook is viable).
-- Turn OFF (false) once we're done investigating. See docs/native_phone_probes.md.
Config.probeNativePhone      = true
Config.enableSchedule        = true
Config.scheduleCheckInterval = 2.0     -- seconds between schedule/proximity checks
Config.proximityRadius       = 45.0    -- metres: idle Jackie appears when you're this close to his spot

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
  idle     = 6,      -- 6 = Smile (5 = Joy, 2 = Neutral)
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

-- ---- send Jackie off (v0.33) ---------------------------------------------
-- A dialogue choice that is ALWAYS shown while Jackie is your COMPANION (following you).
-- Picking it ends the talk, Jackie says a parting line, his follower role is dropped and he
-- WALKS AWAY; once he is `despawnDistance` m from V (or `maxSeconds` pass) he despawns. This
-- is the immersive opposite of the instant "Dismiss Jackie" hotkey.
Config.dismiss = {
  choiceText      = "Head home, Jackie. I got this from here.",  -- silent V line in the choice box
  partingSfx      = "jl_1155727714874494976",   -- Jackie VO: "Time we were on our way, mamita."
  partingText     = "Time we were on our way, mamita.",
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
-- ✅ v0.84: RE-ENABLED. The old load crash was a timing bug: startupGrace was measured against JL.clock
-- (time since onInit), but a mid-session load-from-save does NOT re-run onInit, so JL.clock was already
-- huge and the grace was skipped -> we spawned into a still-streaming world = crash. companionPersistTick
-- now measures the grace from when the PLAYER re-enters the world (resets on every load / district FT) AND
-- refuses to spawn until AMM has re-initialised + Jackie's record resolves. Same spawn path the confirmed
-- catch-up respawn (bug 2f) already uses safely. If a load crash EVER recurs: raise startupGrace first.
Config.persist = {
  enabled       = true,   -- v0.84: back on (crash fixed — grace now measured from world-ready, AMM-gated)
  startupGrace  = 8.0,    -- s of settled, in-world time (from when the player appears) before we spawn
  gapSustain    = 1.5,    -- s the "should be here but isn't" condition must hold (rides out stream hiccups)
  cooldown      = 5.0,    -- s between respawn attempts (also covers the spawn->promote resolve window)
}

-- ---- walk-abreast (v0.84) -------------------------------------------------
-- When ON, a settled companion Jackie holds a spot BESIDE / slightly AHEAD of V (offset from V's forward
-- vector) instead of trailing behind on the keep-close leash — for the "walk next to me to dinner" feel.
-- Tune it LIVE from the CET "Walk abreast" panel: `angleIndex` is a clock position around V (of `positions`
-- steps) — 0 = dead ahead, 3 = V's right, 6 = behind, 9 = left; `radius` is how far out. When enabled it
-- REPLACES followKeepCloseTick (they'd fight otherwise). Starts OFF so nothing changes until you toggle it.
-- Once a spot feels right in-game, tell Claude the index+radius to bake here and wire into the dinner walk.
Config.abreast = {
  enabled    = false,   -- toggled live from CET; off = normal trailing keep-close follow
  positions  = 12,      -- number of clock steps around V the slider cycles through
  angleIndex = 2,       -- default 2/12 = 60° off forward (ahead-right); slider overrides live
  radius     = 2.0,     -- metres from V he holds
  interval   = 1.0,     -- s between re-issues of the move-to-offset-point command
  movement   = "Run",   -- "Walk" | "Run" | "Sprint" — how he closes to the abreast spot
  tolerance  = 0.5,     -- desiredDistanceFromTarget for the move command
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
  distance = 1.5,    -- metres he keeps behind V (Antonia's tuned default, 2026-07-01)
  interval = 1.5,    -- seconds between follow re-asserts
  movement = "Run",  -- "Walk" | "Run" | "Sprint" — how he closes the gap when he drifts back
}

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
  objectiveText     = "Grab some food with Jackie: Go to %s",  -- neon-left flash when the walk starts (%s = place)
  objectiveDuration = 6.0,                                     -- seconds the flash stays up

  venuesShown       = 4,     -- v0.52: only this many RANDOM venues (of the full pool) are offered per picker

  -- Restaurants V can pick. pos/yaw reuse coords already captured in Config.locations (his bar/stall
  -- waypoints) so he sits facing the right way. Each entry WITH pos auto-becomes a dialogue option.
  -- pickText/pickSfx (v0.52): Jackie's spoken line when HE picks this spot (the "You pick, hermano." path).
  -- Only venues WITH a pickSfx are eligible for his self-pick, so he can actually NAME where they're going.
  restaurants = {
    { key = "noodle",    name = "the noodle bar", pos = { -1441.064, 1257.748,  23.090 }, yaw =  -87.1 },  -- noodle bar
    { key = "redwood",   name = "Redwood Market", pos = {  -431.550,  669.948, 115.010 }, yaw =  -33.5 },  -- "noodle place" stall
    { key = "afterlife", name = "Afterlife",      pos = { -1449.437, 1012.129,  17.357 }, yaw = -168.3,    -- barstool, right side
      pickText = "...then I say we hit the Afterlife, hahaha... You know, do some shots.", pickSfx = "jl_1790891785270616064" },
    { key = "ginger",    name = "Ginger Panda",   pos = {  -485.426,  576.939,  31.302 }, yaw =  -17.1 },  -- the bar
    { key = "lizzies",   name = "Lizzie's Bar",   pos = { -1174.427, 1572.135,  23.115 }, yaw =  -68.5,    -- rear bar
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
          { text = "Man, this hits the spot. No gigs, no gunfire — just us." },
          { text = "Could get used to this quiet-life thing, y'know?" },
          { text = "Good to just sit a minute, huh, chica?" },
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
          { text = "Night City don't care if you live or die, chica. All you can do is find your people and hold on tight." },
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
        jackiePool = {
          { text = "Misty's my anchor, V. Keeps me lookin' up when I wanna look down. Dunno what I'd be without her." },
          { text = "Me an' Misty? Solid. She reads them cards, says the stars got a plan. I just tell her she's my plan." },
        },
        choices = {
          { text = "She's good for you.", to = "open"  },
          { text = "Let's get movin'.",   to = "leave" },
        },
      },
      leave = {
        -- terminal (no choices) + action -> after his line, dinnerTick stands him up + re-follows.
        jackiePool = {
          { text = "Heh, alright. Let's roll, chica." },
          { text = "Yeah, we got a city to look after. Vamonos." },
          { text = "Right behind ya, hermano. Let's move." },
        },
        action = "dinner_leave",
      },
    },
  },
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
        choices = {
          { text = "Things good with Misty?", to = "her"   },
          { text = "She read your cards yet?", to = "cards" },
          { text = "I'll leave you to it.",    to = "bye"   },
        },
      },
      her = {
        jackie  = { text = "Now I go back, find Misty and we do somethin' to make me feel alive again.", sfx = "jl_1677043911795367936" },
        choices = {
          { text = "Glad you got her. Take care, hermano.", to = "bye" },
          { text = "When you surface, got a side gig.",      to = "gig" },
        },
      },
      cards = {
        jackie  = { text = "Misty knew... Misty always knows...", sfx = "jl_2024290835469197312" },
        choices = {
          { text = "Spooky. Later, choom.",            to = "bye" },
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
        -- v0.81: each sign-off shows a RANDOM line from its textPool (re-rolled every open, like the
        -- jackiePool above), so it never sounds canned. Left pool leads to his "you take it easy, rest
        -- up" reply (`care`); right pool leads to his "time we were on our way" reply (`bye`).
        choices = {
          { textPool = {
              "Just checkin' in on ya, hermano.",
              "Take care of yourself, choom.",
              "Look after yourself, yeah?",
              "Get some rest, you earned it.",
            }, to = "care" },
          { textPool = {
              "We should get movin'.",
              "Let's get goin', hermano.",
              "Alright, I'm headin' out.",
              "Time to hit the road, choom.",
            }, to = "bye"  },
        },
      },
      care = {
        jackie  = { text = "Thanks, I will! V, you take it easy, OK? Rest up a bit.", sfx = "jl_1993514843414274048" },
        -- v0.81: no (Leave) menu — this is the last line, so it auto-closes the dialogue box.
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
  bikeRecord       = "Vehicle.v_sportbike2_arch_jackie_player",  -- Jackie's Arch
  -- v0.63: appearance name for the bike-model test (method M2). The arrival sometimes spawns the
  -- WRONG model/livery; once the "Bike model test" buttons + console read-back tell us the exact
  -- appearance of his real Arch, set it here and we'll lock it into the live arrival spawn.
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
  useNativeWindow   = true,          -- ON (Antonia's design): RING (IncomingCall ~2s) -> STOP (EndCall,
                                   --   aborts the canned native call) -> CONNECT (StartCall, the empty
                                   --   transparent window) -> our branching voice convo runs over it ->
                                   --   random V farewell -> hang up (EndCall). false = text "Calling..." only.
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
-- The FIRST holocall after Jackie's back plays Config.firstCallTree instead of the normal
-- callTree: he's relieved/happy and asks for his Arch back. When V agrees (the "return_bike"
-- action), his bike is removed from V's garage — it's his ride again now that he's alive.
-- One-time, persisted via the game fact below (see jlReturnJackiesBike in init.lua).
Config.bikeReturn = {
  enabled    = true,
  bikeRecord = "Vehicle.v_sportbike2_arch_jackie_player",  -- Jackie's Arch (same record the arrival uses)
  fact       = "jackielives_bikeback",
  -- keyItem  = "Items.SomeBikeKey",   -- optional: vanilla 2.x has no bike-"key" item, so leave unset
}

-- The one-time reunion call. Same node format as Config.callTree. Text-only Jackie lines are fine
-- here (same as seatedTree) — swap in real VO by adding `sfx = "jl_<id>"` once matching lines are found.
Config.firstCallTree = {
  start = "hey",
  nodes = {
    hey = {
      jackiePool = {
        { text = "V! Damn... it's good to hear your voice, chica. Wasn't sure I'd ever get to say that again." },
      },
      choices = {
        { text = "Good to hear yours too, Jackie.",   to = "bike" },
        { text = "You had me buryin' you, choom.",    to = "bike" },
      },
    },
    bike = {
      jackiePool = {
        { text = "Listen, one thing's been eatin' at me. My Arch — Vik says you kept her safe all this time. She still purrs?" },
      },
      choices = {
        { text = "She's yours. I'll bring her by.",       to = "thanks" },
        { text = "Kept her warm for you, hermano.",       to = "thanks" },
      },
    },
    thanks = {
      -- terminal (no choices) -> random V farewell -> hang up. The node-level action fires at
      -- hang-up (a choice's action would be overwritten on reaching this terminal node, so it
      -- MUST live here — same pattern as callTree's gig/summon_arrival).
      jackiePool = {
        { text = "Heh. Knew it. Bring her round and come see me, yeah? We got a lotta catchin' up to do." },
      },
      action = "return_bike",
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
-- OUTFITS (v0.39): each location carries an `appearance` — Jackie's REAL AMM appearance name
-- (confirmed in-game by Antonia). Wardrobe mapping:
--   jackie_welles_default               -> noodle, coyote, test, and the summon/arrival fallback
--   jackie_welles_default_collar_down   -> misty, afterlife, redwood
--   jackie_welles__q000_lizzies_club_no_jacket -> ginger (Ginger Panda) + lizzies (Lizzie's Bar)
--   jackie_welles__q005_suit            -> reserved for a future "date" day (not used at a location yet)
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

return Config
