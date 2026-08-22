-- tools/test_talk_prompt.lua — the v1.8.9 regression: the text prompt is a reminder, not a heartbeat.
--
-- Run from the repo root:   luajit tools/test_talk_prompt.lua mod/JackieLives/init.lua
-- Exits non-zero on failure. Stock Lua 5.x, no game, no CET.
--
-- THE BUG IT PINS (2026-08-22, and the Nexus comments): *"the 'Talk to Jackie [F]' notification
-- message ... is spamming continuously every few seconds when you hover over the NPC."*
-- The plain-text prompt re-pushed itself every 2.5 s for as long as you kept looking, and
-- showOnscreenMsg writes a FRESH SimpleScreenMessage to the UI_Notifications blackboard each time —
-- so the game replayed the slide-in animation over and over. That slot is also the game's OWN notice
-- band, so the re-push stomped level-ups and quest updates while you looked at your companion.
--
-- updateTalkPrompt is a file-LOCAL, so it is EXTRACTED and run here against stubs. Every upvalue it
-- closes over (talkUI, choiceBox, Branch, ...) resolves to a global in the extracted chunk, which is
-- exactly what makes this possible — and why the stubs below have to be named precisely.

local SRC = arg[1] or "mod/JackieLives/init.lua"
local srcf = assert(io.open(SRC, "r"), "cannot read " .. SRC .. " — run this from the repo root")
local src = srcf:read("a"); srcf:close()
local s0 = src:find("\nlocal function updateTalkPrompt%(")
assert(s0, "could not find updateTalkPrompt — renamed? then fix this harness")
local body = src:sub(s0 + 1, (src:find("\nend\n", s0) or 0) + 4)
body = body:gsub("^local function", "function")        -- make it callable from out here

local fails = 0
local function check(name, cond, extra)
  print((cond and "ok   " or "FAIL ") .. name .. (extra and ("   " .. tostring(extra)) or ""))
  if not cond then fails = fails + 1 end
end

-- ---------------------------------------------------------------------------
-- the stubbed world
-- ---------------------------------------------------------------------------
local BODY = { GetWorldPosition = function() return { x = 0, y = 0, z = 0 } end }
local LOOKING = true                    -- what the raycast currently answers

banners = 0                             -- every showOnscreenMsg call = one animated notification
boxPushes = 0

talkUI    = {}
choiceBox = { shown = false }
Branch    = { busy = false }
Allies    = { present = function() return false end }
Blaze     = {}
JL       = { clock = 0, mode = "quietlife" }
Lang      = { t = function(x) return x end }
Config    = { talk = { range = 6.0, keyLabel = "F", useChoiceBox = false,
                       boxRefresh = 1.0,
                       prompt = "text", textRearmSeconds = 2.0 } }

function jlInCutscene() return false end
function jlIsOurBody() return true end
function playerPos() return { x = 0, y = 0, z = 0 } end
GAP = 1.0
function dist3() return GAP end
function lookedAtJackie() return LOOKING and BODY or nil end
function showOnscreenMsg() banners = banners + 1 end
function showJackieChoiceBox() boxPushes = boxPushes + 1; choiceBox.shown = true; choiceBox.lastPush = JL.clock end
function hideJackieChoiceBox() choiceBox.shown = false end
function log() end

load(body)()

local DT = 1 / 60
local function frames(seconds)
  for _ = 1, math.floor(seconds / DT) do
    JL.clock = JL.clock + DT
    updateTalkPrompt(DT)
  end
end
local function reset()
  banners, boxPushes = 0, 0
  talkUI, choiceBox = {}, { shown = false }
  JL.clock, LOOKING, GAP = 0, true, 1.0
end

-- ---------------------------------------------------------------------------
print("1. THE REGRESSION — looking at them for a long time shows the banner ONCE")
reset()
frames(30.0)
check("one banner in 30 s of looking", banners == 1,
      ("%d banners — the old heartbeat produced ~12 here"):format(banners))

print("\n2. a flickering raycast must not re-trigger it")
-- lookedAtJackie raycasts a MOVING body; it drops out for a frame or two while they walk. Re-arming
-- on the first false frame would put the spam straight back, with extra steps.
reset()
frames(1.0)
check("shown once", banners == 1)
for i = 1, 40 do                                   -- ~0.7 s of alternating hit/miss
  LOOKING = (i % 2 == 0)
  JL.clock = JL.clock + DT
  updateTalkPrompt(DT)
end
LOOKING = true
frames(3.0)
check("a flickering look does NOT re-show it", banners == 1,
      ("%d banners — the re-arm is firing on single false frames"):format(banners))

print("\n3. a real look-away, then back, does show it again")
reset()
frames(1.0)
check("shown once", banners == 1)
LOOKING = false; frames(3.0)                       -- well past textRearmSeconds (2.0)
LOOKING = true;  frames(1.0)
check("looking away and back re-arms it", banners == 2, banners)

print("\n4. 'None' draws nothing at all, however long you look")
reset()
Config.talk.prompt = "off"
frames(30.0)
check("no banner in None mode", banners == 0, banners)
Config.talk.prompt = "text"

print("\n5. the NATIVE box keeps its heartbeat — it is a different mechanism")
-- The box is a blackboard field the game can clear from under us, so re-asserting it is load-bearing.
-- Re-asserting a box already on screen changes nothing visually; re-pushing a notification re-animates.
reset()
Config.talk.useChoiceBox = true
frames(10.0)
check("the box is re-asserted while looking", boxPushes >= 5,
      ("%d pushes — the box heartbeat must NOT be removed with the banner one"):format(boxPushes))
check("...and no text banner was drawn in box mode", banners == 0, banners)
Config.talk.useChoiceBox = false

-- ⚠️ NO SECTION 6 HERE. NCLives/NCLucy have a "release F to another mod" switch that falls
-- through to the text prompt; JackieLives has never had one (F is the only way in), so there is
-- no nativeInteractKey gate in its updateTalkPrompt to exercise. Do not port that section back
-- without porting the switch first.

print("\n7. the banner is a CLOSE-UP reminder, not a room-wide one")
-- Reported 2026-08-22 by the player who turned the F switch off: "then I had a message
-- 'Talk to Jackie [F]' showing ... from a distance of several meters away as well." Both styles share
-- Config.talk.range (6 m), but the native box is an offer the GAME filters through its own, much
-- shorter interaction range before drawing — so switching styles moved the prompt from ~2 m to 6 m.
reset()
GAP = 5.0                                          -- inside talk range (6), outside textRange (3)
frames(5.0)
check("no banner from 5 m away", banners == 0,
      ("%d banners — textRange is not being applied"):format(banners))
GAP = 2.0                                          -- ...and now V walks up to her
frames(1.0)
check("...and it appears once you are close", banners == 1, banners)

-- The KEY is deliberately still live at the full range; only the reminder is close-up. talkUI.shown
-- is what the rest of the engine reads for "in talk range and looking", so it must stay TRUE out
-- there — dropping it would be a silent behaviour change to everything that consults it.
reset()
GAP = 5.0
frames(1.0)
check("...but we still report being in talk range at 5 m", talkUI.shown == true,
      "talkUI.shown must not be narrowed by the DRAW range — other systems read it")

print("")
if fails > 0 then print(fails .. " FAILED"); os.exit(1) end
print("ALL PASS")
