-- Jackie Lives — configuration
-- Antonia edits THIS file. Coordinates are captured in-game (see README).

local Config = {}

-- ---- master toggles -------------------------------------------------------
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
  range      = 4.0,    -- metres; must be looking at Jackie within this distance
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
  cycleHint = "-",
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

-- ---- locations ------------------------------------------------------------
-- Capture coords in-game with the "Capture current position" button, then paste
-- the printed line into the matching entry below. `pos = { x, y, z }`, yaw in degrees.
-- Leave pos = nil until captured (Jackie just won't idle-spawn there yet).
Config.locations = {
  -- captured 2026-06-16 (Antonia). sitNearest = true -> Jackie tries to sit on the nearest
  -- chair/seat workspot once he idle-spawns here (see TODO: chair-sit feature).
  noodle    = { name = "Noodle bar",          pos = { -1441.064, 1257.748, 23.090 }, yaw = -87.1, sitNearest = true },
  -- Misty REPLACES Vik/Vic as a destination (Antonia). Captured 2026-06-16:
  misty     = { name = "Misty's Esoterica",   pos = { -1541.072, 1195.238, 15.869 }, yaw = 50.9 },
  coyote    = { name = "El Coyote Cojo",      pos = nil, yaw = 0.0 },
  afterlife = { name = "Afterlife",           pos = nil, yaw = 0.0 },
  -- captured 2026-06-16 for the native-box test (your standing spot in the test save):
  test      = { name = "Test spot",           pos = { -854.737, 1833.329, 36.207 }, yaw = 44.4 },
}

-- ---- daily schedule -------------------------------------------------------
-- One state per time-of-day block (24h game time). A block wraps past midnight
-- when endHour < startHour. state = "at_location" (needs locationKey) or "unavailable".
-- Mapping assumed from your note (daytime noodle → evening bar → nightlife → asleep);
-- swap the locationKeys if you want a different order.
Config.schedule = {
  { startHour = 8,  endHour = 14, state = "at_location", locationKey = "noodle"    },
  { startHour = 14, endHour = 20, state = "at_location", locationKey = "coyote"    },
  { startHour = 20, endHour = 2,  state = "at_location", locationKey = "afterlife" },
  { startHour = 2,  endHour = 8,  state = "unavailable"                            },
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
