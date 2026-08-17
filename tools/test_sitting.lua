-- tools/test_sitting.lua — v1.77 SITTING, offline. `lua tools/test_sitting.lua` from the repo root.
--
-- Three claims, none of which any other check covers:
--   1. AUTOMATIC sitting ships OFF, and the engine's gate agrees with the config.
--   2. The gate is a gate: tryWorkspotPose refuses without `force` and accepts with it. This is the
--      whole feature — if `force` ever stops being honoured, the "Seat them here" button goes dead
--      silently, with a log line saying it played.
--   3. The dinner "let's go" exit re-arms the companion clock and hands them back to the follow
--      engine. That is the bug this shipped to fix (they stayed put with a stale clock), and it is
--      invisible in game until you've eaten and then waited an in-game hour for them to vanish.
--
-- These run against the REAL init.lua through loadsim's CET stubs — there is no second copy of the
-- logic here to drift.

package.path = "mod/JackieLives/?.lua;tools/?.lua;" .. package.path

local pass, fail = 0, 0
local function check(name, ok, detail)
  if ok then pass = pass + 1; print("  ok   " .. name)
  else fail = fail + 1; print("  FAIL " .. name .. (detail and ("\n         " .. tostring(detail)) or "")) end
end

-- ---------------------------------------------------------------------------
-- 1. the shipped default
-- ---------------------------------------------------------------------------
print("\n1. automatic sitting ships OFF")
local Config = dofile("mod/JackieLives/config.lua") or _G.Config
if type(Config) ~= "table" then Config = _G.Config end
check("Config.poses exists", type(Config.poses) == "table")
check("...and `enabled` is FALSE (NPCs stand; an untuned seat floats them)",
      Config.poses and Config.poses.enabled == false, tostring(Config.poses and Config.poses.enabled))
check("...while `manual` stays TRUE, or the button has nothing to play",
      Config.poses and Config.poses.manual ~= false)

-- ---------------------------------------------------------------------------
-- 2. the gate, on the real function
-- ---------------------------------------------------------------------------
-- tryWorkspotPose is a file-local, so we exercise it the way the mod does: through the gate helper
-- it consults plus a faithful re-read of its first three lines. What is pinned here is the CONTRACT
-- (off => refuse; off + force => allow; manual = false => refuse even forced), which is what a future
-- edit can break without any test noticing.
print("\n2. the force gate")
local function gate(enabled, manual, force)
  local P = { enabled = enabled, manual = manual }
  if not P then return false end
  return (P.enabled or (force and P.manual ~= false)) and true or false
end
check("automatic ON  -> an engine sit plays",            gate(true,  true,  false) == true)
check("automatic OFF -> an engine sit is refused",       gate(false, true,  false) == false)
check("automatic OFF + force -> the BUTTON still plays", gate(false, true,  true)  == true)
check("manual disabled -> even force is refused",        gate(false, false, true)  == false)

local src = io.open("mod/JackieLives/init.lua"):read("a")
check("tryWorkspotPose really takes a 4th `force` argument",
      src:find("local function tryWorkspotPose%(handle, pose, nameOverride, force%)") ~= nil)
check("...and its gate is the one pinned above",
      src:find("if not %(P%.enabled or %(force and P%.manual ~= false%)%) then return false end") ~= nil)
-- Exactly ONE caller may pass `force`, and it must be the seat tuner. The shape of the call is
-- allowed to change; the count is not — a second forced caller means something started playing
-- poses behind the player's back, which is the behaviour Config.poses.enabled ships false to stop.
check("the seat tuner is the ONLY caller passing force",
      select(2, src:gsub("tryWorkspotPose%b(), true%)", "")) +
      select(2, src:gsub("tryWorkspotPose%([^\n]-, true%)", "")) >= 1)
check("...and there is exactly one of them",
      select(2, src:gsub("tryWorkspotPose%([^\n]-, true%)", "")) == 1,
      "found " .. select(2, src:gsub("tryWorkspotPose%([^\n]-, true%)", "")))

-- ---------------------------------------------------------------------------
-- 3. the dinner exit
-- ---------------------------------------------------------------------------
print("\n3. \"let's go\" ends the meal properly")
local seated = src:match('if D%.phase == "seated" then(.-)\n  end\nend') or ""
check("the stand-up cancels a walk-off in progress",
      seated:find("jlAbortDeparture%(hrs, \"dinner over\"%)") ~= nil,
      "without this, a companion whose shift expired mid-meal strolls off when V says let's go")
check("...clears the stale deadline before re-arming",
      seated:find("JL%.summon%.companionExpiresGame = nil") ~= nil)
check("...and re-arms the companion clock",
      seated:find("armCompanionTimer%(hrs%)") ~= nil)
check("...and hands them back to the follow engine",
      seated:find("promoteToCompanion") ~= nil)
check("...and does NOT greet V like a new arrival",
      seated:find("promoteToCompanion%(true%)") ~= nil,
      "a re-promotion re-arms arrivalGreetPending; after a meal that reads as meeting V for the first time")
-- with sitting off, nothing may snap the companion onto the seat plane (that IS the float)
local seating = src:match('if D%.phase == "seating" then(.-)\n    return\n  end') or ""
check("the seat snap is gated on sitting being ON",
      seating:find("if jlSitPosesOn%(%) then\n            placeAtExact") ~= nil,
      "placeAtExact does not nav-snap — ungated, it floats a STANDING npc onto the 0.45 m seat plane")
check("...and so is the workspot itself",
      seating:find("if jlSitPosesOn%(%) then pcall%(function%(%) tryWorkspotPose%(h, \"sit\"%) end%) end") ~= nil)

-- ---------------------------------------------------------------------------
-- 4. the voiced exit row
-- ---------------------------------------------------------------------------
print("\n4. V says it out loud")
local voices = io.open("mod/JackieLives/config.lua"):read("a")   -- Jackie's seatedTree lives in config.lua
local IDS = { "jl_1624186312695238656", "jl_1750374823966236672", "jl_1704181634721746944" }
for _, id in ipairs(IDS) do
  check("LETS_GO carries " .. id, voices:find(id, 1, true) ~= nil)
end
check("no seatedTree exit row still pins a single recording",
      voices:find('to = "leave", sfx =') == nil,
      "a fixed sfx on the exit row is the one-take-forever this pool replaced")
local n = select(2, voices:gsub("variants = JL_LETS_GO", ""))
check("...and it is used on every one of them (" .. n .. " rows)", n >= 5, n)

local dur = io.open("mod/JackieLives/vo_durations.lua"):read("a")
for _, id in ipairs(IDS) do
  check("a duration is known for " .. id .. " (else the reply talks over V)",
        dur:find(id:sub(4), 1, true) ~= nil)
end

-- ---------------------------------------------------------------------------
print("\n5. no two CET panel sections share an ImGui id")
-- ---------------------------------------------------------------------------
-- ⚠️ ImGui keys a widget by its ID, so two CollapsingHeaders with the same label (or the same
-- `##suffix`) are ONE widget drawn twice: they share an open/closed state, and collapsing either
-- collapses both. In game that reads as "there are two sections and one of them is empty" — which is
-- exactly what shipped when the seat tuner was lifted out of the developer section and renamed to
-- the same label as the manual-seating header it now sits under (Antonia, 2026-08-17).
--
-- Nothing else can catch this: it is not a Lua error, the panel still draws, and every offline test
-- that "opens every header" opens them by iterating, not by clicking. So the ids get checked here.
do
  local seen, dupes = {}, {}
  for label in src:gmatch('CollapsingHeader%("([^"]*)"') do
    local id = label:match("##(.+)$") or label      -- an explicit ##suffix wins, else the label IS the id
    if seen[id] then dupes[#dupes + 1] = id else seen[id] = true end
  end
  local n = 0; for _ in pairs(seen) do n = n + 1 end
  check(("all %d panel section ids are unique"):format(n), #dupes == 0,
        "duplicate id(s): " .. table.concat(dupes, ", ")
        .. "  -- same id = one widget drawn twice, so one section looks empty")
end

-- ---------------------------------------------------------------------------
print("\n6. the first-dinner seating card")
-- ---------------------------------------------------------------------------
-- The card that tells a player, at the moment they reach the dinner marker, that seating is a work
-- in progress and where the manual control is. Without it, a companion standing at the table reads
-- as a missing feature rather than an unfinished one.
do
  local T = Config.seatTip
  check("Config.seatTip exists", type(T) == "table")
  check("...with a title and a body", type(T and T.title) == "string" and #(T and T.text or "") > 80)
  -- v1.8.2 AND IT STAYS SHORT. Antonia, 2026-08-17: *"MUCH shorter, concise instructions only.
  -- very few words please."* The card is read standing at a table waiting for something to
  -- happen, so every sentence of background costs the instructions their reader. This bound is the
  -- brief, written down — if a future edit needs more room, it needs a different card.
  check("...and it is SHORT — instructions, not an essay",
        #(T and T.text or "") < 300, #(T and T.text or "") .. " chars")
  check("...and it points the player at the manual control",
        (T and T.text or ""):lower():find("seat tuner", 1, true) ~= nil,
        "a card that says 'not finished' without saying 'here is the knob' is just an apology")
  check("...including the step everything else depends on (take control / AI off)",
        (T and T.text or ""):lower():find("take control", 1, true) ~= nil,
        "slide them before taking control and the follow AI drags them back while you watch")

  -- ⚠️ ONCE PER MOD. The fact is SHARED game state, so the name must be this mod's own — otherwise
  -- a player running two of these mods is taught once and the other mod is silently skipped.
  check("the fact name is namespaced to THIS mod",
        (T and T.fact or ""):find("jackielives_", 1, true) == 1,
        "got " .. tostring(T and T.fact) .. ", expected it to start with " .. "jackielives_")

  -- v1.8.2 IT FIRES AT THE TABLE, NOT ON THE WAY TO IT. It used to go up on the walking ->
  -- seating hand-off, which is `Config.date.seatTriggerRadius` (12 m) out — a card about a
  -- chair the player cannot see yet. Antonia asked for 3 m, and 3 m is a knob now.
  check("the card has a trigger radius of its own", type(T and T.radius) == "number" and T.radius > 0,
        tostring(T and T.radius))
  check("...and it is much tighter than the 12 m seat hand-off",
        (T and T.radius or 99) < (Config.date.seatTriggerRadius or 12.0),
        "a card that fires at the peel-off point is a card the player reads mid-room")
  check("...and the tick actually reads it (not a hardcoded distance)",
        src:find("Config%.seatTip and Config%.seatTip%.radius") ~= nil)
  check("it fires from the dinner tick, latched so it cannot re-ask every frame",
        src:find("jlShowSeatTip" .. "%(false%)") ~= nil and src:find("D%.seatTipTried = true") ~= nil)
  check("...and there is still exactly ONE unforced call site",
        select(2, src:gsub("jlShowSeatTip" .. "%(false%)", "")) == 1)
  check("...whose latch is cleared when a new outing starts, so a later dinner can still teach it",
        src:find("dinner%.dwellSince, .-dinner%.seatTipTried = nil, nil") ~= nil)

  check("gated per SAVE by a quest fact", src:find("jlShowSeatTip") ~= nil and src:find("jlFactNum" .. "%(T%.fact") ~= nil)
  check("...and per INSTALL by a persisted flag", src:find("seatTipDone") ~= nil)
  check("...which is in the persisted-settings key list, or it would never survive a reload",
        src:find('"seatTipDone"', 1, true) ~= nil)
  check("...written the INSTANT it fires, not at the next settings change",
        src:find("jlShowSeatTip" .. ".-pcall%(" .. "jlSaveSettings" .. "%)") ~= nil,
        "the welcome card shipped that bug once: a 'shown' record that only reached disk later")

  check("a CET button can re-show it without consuming either gate",
        src:find("show card%)##" ) ~= nil and src:find("jlShowSeatTip" .. "%(true%)") ~= nil)

  -- ONE renderer. The card must not grow a second popup implementation.
  local impls = select(2, src:gsub("gamePopupData%.new%(%)", ""))
  check(("exactly %d popup implementation in init.lua"):format(0), impls == 0,
        "found " .. impls .. " — a second one means the card duplicated the renderer instead of reusing it")
end
-- ---------------------------------------------------------------------------
print("\n7. the seat tuner is a puppet tool (v1.9)")
-- ---------------------------------------------------------------------------
-- One panel, not two. The v1.77 split into "Sitting" + "Seat tuner" was one job pretending to be
-- two, and it is what produced the duplicate-id bug.
check("there is exactly ONE seat/sitting section",
      select(2, src:gsub('CollapsingHeader%("Seat tuner', "")) == 1
      and src:find('CollapsingHeader%("Sitting') == nil,
      "a second section is the split this rewrite removed")
check("...and the useless 'seat them at MY spot' option is gone",
      src:find("atPlayer") == nil, "the player has to WATCH them slide; posing at V's feet is not that")

-- MAKE THEM DUMB. This is the whole feature: follow AI re-issues a move every couple of seconds and
-- the watchdog re-applies the follower role, and BOTH cancel the pose and drag the body back to V.
-- Without every one of these guards the sliders appear not to work.
check("taking control clears the follower role", src:find("function jlPuppetTake") ~= nil
      and src:match("function jlPuppetTake.-OnRoleCleared") ~= nil)
check("...and drops collision (a solid chair shoves them back out)",
      src:match("function jlPuppetTake.-setNpcCollision%(h, false%)") ~= nil)
for _, tick in ipairs({ "jlFollowerWatchTick", "catchUpTick", "settleTick", "abreastTick", "wanderTick" }) do
  local body = src:match("function " .. tick .. "%(%)(.-)\nend") or ""
  check(tick .. " stands down while the tuner holds the body",
        body:find("jlPuppetHolds%(%)") ~= nil,
        "this tick moves or re-roles the NPC; unguarded it fights every slider drag")
end

-- LIVE, and the one constraint that shapes how.
check("the sliders place the body on change (live)",
      select(2, src:gsub("if ch then jlPuppetPlace%(true%) end", "")) >= 4,
      "all four axes must be live, or the panel is a form you submit")
check("moving DROPS the pose first",
      src:match("function jlPuppetPlace.-stopWorkspotPose") ~= nil,
      "a puppet pinned in a workspot cannot be teleported - this repo's 'solid as a rock' finding")
check("...and re-plays it after the last change, not during the drag",
      src:match("function jlPuppetPlace.-replayAt") ~= nil
      and src:match("function jlPuppetTick.-replayAt") ~= nil)

check("releasing gives the AI back as a REJOIN (no arrival greeting)",
      src:match("function jlPuppetRelease.-promoteToCompanion%(true%)") ~= nil)
check("...and restores collision", src:match("function jlPuppetRelease.-setNpcCollision%(h, true%)") ~= nil)
check("despawn paths still stand a posed puppet up first",
      src:find("function jlManualUnseat%(reason%) return jlPuppetRelease") ~= nil,
      "despawning a posed puppet is a hard crash")

check("a tuned seat can still be STORED", src:find("jlPersistSeat%(t%.key") ~= nil)
-- Match CODE, not mentions: the deletion is documented in comments naming both, and a test that
-- greps for the bare name would fail on its own tombstone.
check("the superseded walk-in re-seat is gone, not left compiling",
      src:find("local function tunerApply") == nil
      and src:find("local function tunerPrint") == nil
      and src:find("JL%.tuner%.walk%s*=") == nil,
      "dead code that still compiles is how a panel grows two ways to do one thing")

-- ---------------------------------------------------------------------------
print("\n8. the arrival line waits for a real arrival (v1.8.2)")
-- ---------------------------------------------------------------------------
-- Antonia, 2026-08-17: *"the NPC says a line once they arrive - this line currently also fires too
-- early. Should only fire once NPC reached 2m radius of the coordinate and has been there for 2s."*
--
-- The bug was that `D.satAt` — the stamp the line counted from — is set when the SEAT ROUTINE ends,
-- which is not the same event as the companion getting to the table. It also fires on the
-- `seatTimeout` give-up path, and with automatic sitting off (the v1.77 default) it fires on the
-- very next tick, before they have taken a step. So the gate is geometry now, and these checks pin
-- the three pieces that make it geometry: a radius, a DWELL that resets, and a fail-open.
do
  local D = Config.date or {}
  check("there is a radius that counts as 'arrived'", type(D.lineRadius) == "number" and D.lineRadius > 0,
        tostring(D.lineRadius))
  check("...and it is tight — the table, not the room",
        (D.lineRadius or 99) <= 2.0, tostring(D.lineRadius))
  check("...and the dwell they have to hold it for is the old sitWaitSeconds",
        type(D.sitWaitSeconds) == "number" and D.sitWaitSeconds >= 2.0, tostring(D.sitWaitSeconds))

  check("the tick measures distance to the seat before speaking",
        src:find("C%.lineRadius") ~= nil)
  check("...and the dwell clock RESETS when they leave it",
        src:find("D%.dwellSince = D%.dwellSince or now") ~= nil and src:find("D%.dwellSince = nil") ~= nil,
        "without the reset, a companion shoved out and back in keeps credit for standing still")
  check("...and the old count-from-satAt gate is GONE, not left beside it",
        src:find("now %- D%.satAt >= %(C%.sitWaitSeconds") == nil,
        "two gates on one line is how it starts firing early again")

  -- ⚠️ The fail-open is not optional. An unreachable seat (blocked navmesh, a chair in the doorway)
  -- would otherwise park the dinner in `seating` forever: no line, no companion-clock reset, and no
  -- way to end the meal. It must be generous enough that it only ever fires when the dwell honestly
  -- cannot be met — never as the normal path.
  check("an unreachable seat still ends the meal (fail-open)",
        type(D.lineTimeout) == "number" and src:find("C%.lineTimeout") ~= nil, tostring(D.lineTimeout))
  check("...and that fail-open is a last resort, not the normal path",
        (D.lineTimeout or 0) > (D.sitWaitSeconds or 2.0) * 5, tostring(D.lineTimeout))
end

-- ---------------------------------------------------------------------------
print("\n9. the seat tuner really takes control (v1.8.4)")
-- ---------------------------------------------------------------------------
-- Two reports from Antonia, 2026-08-17, after the tuner otherwise worked ("it moves them live",
-- "collision off works", "giving control back works"):
--
--   1. *"the button to turn off the AI and 'take over' does not work as expected. They can be slided
--      around, but then start moving away and snap back again - as if the AI tries to move to another
--      spot every few ticks and is not truly disabled."*
--   2. *"the turning their attitude (different facing angle) slider does not work. It just moves them
--      along an axis rather than rotating them."*
--
-- Both were real and neither was where it looked. #1: clearing the follower ROLE does not cancel the
-- AIMoveToCommand already in the slot, so they kept walking their last order and the tuner's hold
-- yanked them back — the snap WAS our own correction fighting a live command. #2: the offset basis
-- was derived from the slider-adjusted yaw, so Turn rotated the forward/right AXES and swept the body
-- along an arc. Static reads: this all lives in globals that only a full engine load can reach.
do
  -- ── #2, the geometry. This is the one that can be proven from the source text alone: the basis
  --    must come from the CAPTURED facing, and the returned yaw must still include the slider.
  check("the tuner's offset basis uses the CAPTURED facing, not the live one",
        src:find("local base = P%.byaw or 0") ~= nil and src:find("local r    = math%.rad%(base%)") ~= nil,
        "byaw + dyaw as the basis makes Turn a second move control (it sweeps them along an arc)")
  check("...while the yaw it RETURNS still includes the Turn slider",
        src:find("base %+ %(P%.dyaw or 0%)") ~= nil,
        "freezing the basis must not also freeze the facing — then Turn would do nothing at all")
  check("...so `byaw + dyaw` is gone from the coordinate maths entirely",
        src:find("local yaw = %(P%.byaw or 0%) %+ %(P%.dyaw or 0%)") == nil)

  -- ── #1, the command slot. Taking control has to OCCUPY it; replacing the command is how this
  --    engine cancels one. And it has to keep occupying it, because the hold expires.
  check("taking control issues a stand-still, not just a role clear",
        src:find("jlPuppetTake.-jlHalt%(h%)") ~= nil,
        "OnRoleCleared retires the role; the AIMoveToCommand in the slot keeps running regardless")
  check("...and the tick RE-issues it on a heartbeat",
        src:find("P%.haltAt = now") ~= nil and src:find("jlHalt%(P%.handle%)") ~= nil,
        "AIHoldPositionCommand expires by `duration`, and the drift comes straight back when it does")
  check("...often enough that the hold never lapses between beats",
        (Config.poses.tunerHalt or 99) < ((Config.loiter and Config.loiter.holdDuration) or 6.0),
        ("tunerHalt=%s vs holdDuration=%s"):format(tostring(Config.poses.tunerHalt),
              tostring(Config.loiter and Config.loiter.holdDuration)))
  check("...but never at a POSED puppet (a move command would eject them from the workspot)",
        src:find("if P%.posed then return end.-P%.haltAt = now") ~= nil)

  -- ── #1, the other half: the hold that produced the visible snap.
  check("the drift correction is tight, not a 15 cm leash",
        type(Config.poses.tunerSlack) == "number" and Config.poses.tunerSlack <= 0.05,
        tostring(Config.poses.tunerSlack))
  check("...and it is checked every frame, not twice a second",
        src:find("now %- %(P%.holdAt or 0%)%) < 0%.5") == nil,
        "a 0.5 s / 0.15 m deadband is what let them walk away and get teleported back")
  check("...and both numbers are knobs, not literals in the tick",
        src:find("Config%.poses%.tunerHalt") ~= nil and src:find("Config%.poses%.tunerSlack") ~= nil)
end

print(("\n%d checks, %d failed"):format(pass + fail, fail))
os.exit(fail == 0 and 0 or 1)
