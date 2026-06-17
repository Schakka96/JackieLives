-- Jackie Lives — configuration
-- Antonia edits THIS file. Coordinates are captured in-game (see README).

local Config = {}

-- Mod version. Bump on every deploy; deploy.ps1 prints it and init.lua logs it on load.
Config.version = "0.46"

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

-- ---- companion duration (v0.39) ------------------------------------------
-- Jackie won't stay a merc forever - he heads home on his own after `maxGameHours` IN-GAME
-- hours as your companion (timer measured in game time, not real time). Asking him to dinner
-- (Config.date) RESETS that clock. Set autoLeaveOnExpiry=false to disable the auto-departure.
Config.companion = {
  maxGameHours      = 6.0,   -- in-game hours he'll tag along before heading home on his own
  autoLeaveOnExpiry = true,  -- when the clock runs out he walks off (reuses the send-off exit)
}

-- ---- ask Jackie to dinner / a date (v0.41 - restaurant walk) -------------
-- While Jackie is your COMPANION, the talk menu offers a dinner invite. V then picks a specific
-- restaurant; the mod sets a MAP WAYPOINT there (white dot) + a blue on-screen OBJECTIVE, keeps
-- Jackie following, and when V ARRIVES (<seatTriggerRadius) Jackie walks to HIS seat, plays the
-- sit anim, waits, says one line, and the companion clock FULLY RESETS (once per 24 in-game hours).
-- When V walks off (>getUpRadius) Jackie gets up, says a line, and re-follows. He stays our
-- companion (never despawns) the whole time. No quest/WolvenKit - a Lua state machine (dinnerTick).
Config.date = {
  inviteText           = "Hey - you hungry? Let's grab a bite, just us.",  -- the menu option (V's invite)
  unlockAfterGameHours = 1.0,    -- the invite only appears after this long together...
  enforceUnlock        = false,  -- ...OFF for now (always show, for testing). Flip true to gate it.

  seatTriggerRadius = 12.0,  -- metres: V this close to the spot -> Jackie peels off to his seat
  seatReachRadius   = 2.0,   -- metres: Jackie this close to his seat -> snap + sit
  seatTimeout       = 12.0,  -- v0.44 seconds: if he can't path within seatReachRadius by now, snap+sit anyway
  sitWaitSeconds    = 2.0,   -- seconds seated before he says his line + the clock resets
  getUpRadius       = 10.0,  -- metres: V this far from seated Jackie -> he gets up + re-follows
  resetCooldownHours = 24.0, -- the dinner FULL reset can only fire once per this many in-game hours
  objectiveText     = "Dinner with Jackie - meet him at %s",  -- blue on-screen objective (%s = place)

  -- Restaurants V can pick. pos/yaw reuse coords already captured in Config.locations (his bar/stall
  -- waypoints) so he sits facing the right way. Each entry WITH pos auto-becomes a dialogue option.
  restaurants = {
    { key = "noodle",    name = "the noodle bar", pos = { -1441.064, 1257.748,  23.090 }, yaw =  -87.1 },  -- noodle bar
    { key = "redwood",   name = "Redwood Market", pos = {  -431.550,  669.948, 115.010 }, yaw =  -33.5 },  -- "noodle place" stall
    { key = "afterlife", name = "Afterlife",      pos = { -1449.437, 1012.129,  17.357 }, yaw = -168.3 },  -- barstool, right side
    { key = "ginger",    name = "Ginger Panda",   pos = {  -485.426,  576.939,  31.302 }, yaw =  -17.1 },  -- the bar
    { key = "lizzies",   name = "Lizzie's Bar",   pos = { -1174.427, 1572.135,  23.115 }, yaw =  -68.5 },  -- rear bar
  },

  -- v0.43: walk/arrival BANTER fully disabled (Antonia). The only spoken beats are the three below.
  -- Jackie's single-line beats (real-matching clips; the restaurant NAME shows via the waypoint + objective):
  ackText    = "Right on, chica.",                  ackSfx    = "jl_1721407637774192672",  -- on accept (heading out)
  doneText   = "Gettin' one of my good feelings.",  doneSfx   = "jl_1834502468175589376",  -- seated, 2s after sitting (reset)
  getUpText  = "Why, what's the rush?",             getUpSfx  = "jl_1989527454849245184",  -- V walks off -> he gets up
  -- v0.43b: he won't go out to eat twice a day. If asked within resetCooldownHours of his last
  -- dinner, he REFUSES with this line and the outing aborts (no walk, no waypoint).
  refuseText = "Yeaaaah. Had enough for one day, lemme tell you.", refuseSfx = "jl_1697051347046326272",

  tree = {
    start = "open",
    nodes = {
      open = {
        restaurantPicker = true,   -- restaurant options are auto-injected here from `restaurants`
        jackiePool = {
          { text = "Man, I'm starvin'. Let's grab a tight-bite. Whaddaya say?", sfx = "jl_1904096844380655616" },
          { text = "Now, whaddaya say we liquor up and talk life.",             sfx = "jl_1661715724513484800" },
          { text = "C'mon. I'm fuckin' starved.",                               sfx = "jl_1834512408575406080" },
        },
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
      choices = {
        { text = "(Leave)", to = nil },
      },
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
        choices = { { text = "(Leave)", to = nil } },
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
        choices = { { text = "(Leave)", to = nil } },
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
        choices = { { text = "(Leave)", to = nil } },
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
        choices = { { text = "(Leave)", to = nil } },
      },
    },
  },

  -- EVERYWHERE (BACKUP: short 2-option exchange; DONE -> 60s grunt-only cooldown)
  everywhere = {
    start = "open",
    cooldownSeconds = 60,   -- after finishing this once, F just grunts until 60s pass
    nodes = {
      open = {
        jackiePool = {
          { text = "Talk to me, choomba.",                                          sfx = "jl_2239163066690486272" },
          { text = "V, how you feel? You all right?",                              sfx = "jl_1802590928224841728" },
          { text = "Don't come here often, do ya? Heheh. Good to see you, chica.", sfx = "jl_1661700260668284928" },
        },
        choices = {
          { text = "Just checkin' in. Take it easy.", to = "care" },
          { text = "Catch you later, hermano.",        to = "bye"  },
        },
      },
      care = {
        jackie  = { text = "Thanks, I will! V, you take it easy, OK? Rest up a bit.", sfx = "jl_1993514843414274048" },
        choices = { { text = "(Leave)", to = nil } },
      },
      bye = {
        jackie  = { text = "Time we were on our way, mamita.", sfx = "jl_1155727714874494976" },
        choices = { { text = "(Leave)", to = nil } },
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
  ringEvent     = "ono_jackie_phone",  -- extra WWise ring SFX layered on ("" = silent)
  spawnDelay    = 2.5,   -- seconds after the call ends before Jackie spawns (was 5.0; halved)
  -- ARRIVAL METHOD — 3 paths, cycled live from the CET window "Arrival method" button:
  --   "safe"   = SAFE WALK-IN (arrivalTick): AMM-spawn near V, HIDE through the pop, AI-teleport to
  --              `spawnDistance`, reveal, jog in -> companion. Rock-solid; the default since v0.44.
  --   "sprint" = SPRINT-IN (vehicleArrivalTick, bikeless): spawn DIRECTLY at the far navmesh point
  --              (clean dynamic-entity spawn — no pop near V, no hide hack), SPRINT in, then WALK the
  --              last `Config.vehicle.sprintToWalk` m before companion.
  --   "bike"   = VEHICLE ARRIVAL (vehicleArrivalTick + bike): spawn his Arch + Jackie behind V, mount,
  --              ride in, dismount near you, sprint -> walk -> companion. Being nursed back to health.
  arrivalMethod        = "safe",
  vehicleSpawnDelay    = 1.0,   -- seconds after the call ends before the sprint-in / bike Jackie spawns
  -- v0.31 SPAWN-AT-DISTANCE + WALK-IN:
  -- He spawns this far from V, snapped onto the navmesh (NavigationSystem) so he never lands
  -- inside a wall/object, then WALKS in. During the walk he is a PASSIVE NPC (no follower
  -- role) so the companion catch-up TELEPORT can't skip the distance we put between you; he
  -- becomes a real companion (combat + follow) only once he's within `companionDistance` of V.
  -- NOTE ON 100 m: that's near the edge of NPC render distance (~100 m) and a long city path.
  -- At "Walk" 100 m is ~90 s, so the approach defaults to "Run" (~25-30 s). For a casual
  -- stroll-up, drop spawnDistance to ~30-40 m and set approachMovement = "Walk".
  -- v0.33c: hideOnSpawn CONFIRMED working (Antonia) -> back ON. The other two arrival vars
  -- (spawnBehind, spawnDistance) + arriveDistance are now A/B-testable live from the CET window
  -- ("Arrival test modes" buttons) so we can dial in the best feel. Values below are the
  -- starting point; the buttons mutate them at runtime.
  spawnDistance    = 80.0,   -- metres from V he spawns at (navmesh-snapped), then walks in
  spawnBehind      = true,   -- spawn BEHIND V (confirmed good); button still toggles for testing
  hideOnSpawn      = true,   -- ON (confirmed): hide through the spawn-pop + teleport, reveal at distance
  approachMovement = "Run",  -- "Walk" | "Run" | "Sprint" -- how he covers the distance to V (a jog)
  -- v0.33d: Sprint was too fast -> the "boost" is now a JOG (Run), same as the steady pace, so he
  -- jogs the whole way in. (Engine has only discrete Walk/Run/Sprint tiers, no continuous speed.)
  approachBoostSeconds  = 15.0,
  approachBoostMovement = "Run",   -- jog (was "Sprint" - too fast over the approach)
  arriveDistance   = 3.0,    -- metres from V the walk-in MoveTo aims to stop short of him
  followDistance   = 1.6,    -- metres the COMPANION keeps after handoff (so he doesn't clip into V)
  -- v0.46: ONE handoff knob for ALL THREE arrival types. He promotes to a real companion (combat +
  -- follow) once he's within this — earlier than before (was 6) so he stops the long solo walk-in
  -- sooner and just follows you. Then, once companion + within `arrivalGruntDistance`, he barks a grunt.
  companionDistance    = 18.0,   -- m: promote to companion at this range (safe / sprint / bike)
  arrivalGruntDistance = 4.0,    -- m: once companion + this close, Jackie barks a "made it" grunt
  maxWalkSeconds   = 90.0,   -- safety: if he hasn't arrived by now, promote anyway (may teleport in)
}

-- ---- SPRINT-IN / VEHICLE ARRIVAL (v0.34, revived v0.46) ---------------------
-- Both non-safe arrivals share this tuning (see Config.call.arrivalMethod):
--   "sprint" — Jackie spawns DIRECTLY at the far navmesh point (clean dynamic-entity spawn, no pop
--              near V), SPRINTS toward V, downshifts to a WALK for the last `sprintToWalk` m.
--   "bike"   — his Arch + Jackie spawn behind V, he mounts, rides in at `cruiseSpeed` (re-targeting
--              V every `retargetInterval`), parks + dismounts at `dismountDistance`, then the SAME
--              sprint -> walk finish. STUCK FAILSAFE + fresh-respawn FOOT FALLBACK cover a broken ride.
-- Both promote to companion at `Config.call.companionDistance` (18 m), not `arriveDistance`.
Config.vehicle = {
  spawnDistance    = 80.0,   -- metres from V Jackie (and the bike) spawn at (navmesh-snapped, rear arc)
  sprintToWalk     = 25.0,   -- Jackie->V distance where he downshifts sprint -> walk (last 25 m on foot)
  arriveDistance   = 3.0,    -- Jackie->V distance the foot MoveTo aims to stop short of him
  -- --- BIKE KNOBS (used by "bike" arrival) ---
  bikeRecord       = "Vehicle.v_sportbike2_arch_jackie_player",  -- Jackie's Arch
  cruiseSpeed      = 8.0,    -- drive speed (8 = careful; he was reckless at higher)
  retargetInterval = 3.0,    -- re-issue the drive at V's latest position (longer = less re-path stutter)
  dismountDistance = 40.0,   -- bike->V distance at which he parks the bike + gets off (was 20)
  -- STUCK FAILSAFE: if the bike crawls (< stuckSpeed m/s) for stuckSustain s, after a
  -- stuckGrace beat at the start (he's still climbing on), he parks early + sprints in on foot.
  -- Covers dense areas where the bike can't path.
  -- (loosened: he was ditching the bike almost always. Only TRULY stuck counts now.)
  stuckSpeed       = 1.0,    -- m/s; below this = likely stuck (was 2.0)
  stuckGrace       = 4.0,    -- seconds after mounting before stuck-detection starts (was 5)
  stuckSustain     = 4.0,    -- seconds of crawling before he bails off the bike (was 2)
  maxSeconds       = 120.0,  -- safety: force the companion handoff if the ride-in stalls
  -- FRESH-RESPAWN FALLBACK (v0.38): the bike ride often breaks. If the arrival hasn't handed off
  -- to a companion within `fallbackSeconds`, give up on the bike entirely: despawn the bike AND
  -- Jackie, respawn him FRESH ~`fallbackDistance` m away on the navmesh, and switch to the plain
  -- on-foot sprint/walk arrival. Fires once per arrival; the maxSeconds teleport is the last resort.
  fallbackSeconds  = 40.0,   -- no companion handoff by now -> fresh on-foot respawn
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
        { text = "Gettin' one of my good feelings.",                             sfx = "jl_1834502468175589376" },
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
    name = "Noodle bar", appearance = "jackie_welles_default", pos = { -1441.064, 1257.748, 23.090 }, yaw = -87.1, sitNearest = true,
    exitWaypoint = { pos = { -1440.553, 1258.332, 23.099 }, yaw = -108.3 },   -- outside the stall (may not reach if unloaded)
    waypoints = {
      { pos = { -1441.064, 1257.748, 23.090 }, yaw = -87.1, pose = "sit" },   -- barstool
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
  startHour   = 0,       -- sleep window (matches the daySchedules 00:00-06:00 asleep block)
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
