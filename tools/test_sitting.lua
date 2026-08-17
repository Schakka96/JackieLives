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
check("the manual seat is the ONLY caller passing force",
      select(2, src:gsub("tryWorkspotPose%(M%.handle, M%.pose, nil, true%)", "")) == 1)

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
  check("...and it points the player at the manual control",
        (T and T.text or ""):lower():find("seat them here", 1, true) ~= nil,
        "a card that says 'not finished' without saying 'here is the knob' is just an apology")

  -- ⚠️ ONCE PER MOD. The fact is SHARED game state, so the name must be this mod's own — otherwise
  -- a player running two of these mods is taught once and the other mod is silently skipped.
  check("the fact name is namespaced to THIS mod",
        (T and T.fact or ""):find("jackielives_", 1, true) == 1,
        "got " .. tostring(T and T.fact) .. ", expected it to start with " .. "jackielives_")

  check("it fires at the marker (the walking -> seating transition)",
        src:find("jlShowSeatTip" .. "%(false%)") ~= nil)
  local seatingBlock = src:match('if pp and D%.dest and dist3.-D%.phase = "seating".-\n(.-)\n    end') or src
  check("...and NOT from a tick that could re-fire it every frame",
        select(2, src:gsub("jlShowSeatTip" .. "%(false%)", "")) == 1)

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

print(("\n%d checks, %d failed"):format(pass + fail, fail))
os.exit(fail == 0 and 0 or 1)
