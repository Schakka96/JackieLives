-- tools/test_dismiss.lua — v1.77. `lua tools/test_dismiss.lua` from the repo root.
--
-- Two reports from 2026-08-17, both of which read as "the mod is broken" and neither of which any
-- existing check could see:
--
--   1. "when dismissing them in person they just despawn" — the walk-off was fully implemented and
--      byte-identical to JackieLives. What was wrong were the two RADII: return-to-post handed the
--      body to the idle system out to 100 m, but the schedule only KEEPS an idle body within 45 m,
--      so a dismissal in that band was an instant clearIdle() with no walk and no parting line.
--      This file pins the two radii to each other, because they are in different files and nothing
--      else connects them.
--
--   2. "I often saw Kerry spawn naked" — the appearance rides on the spawn spec, which loses a
--      streaming race. AMM prefetches and applies AFTER the body exists; we now do both. The ORDER
--      matters (prefetch, then schedule) and is the thing a future edit can silently invert.
--
-- Static reads of the real sources: the behaviour lives in file-locals and in tick order, neither of
-- which a stub harness can reach without re-implementing them (and a re-implementation drifts).

local pass, fail = 0, 0
local function check(name, ok, detail)
  if ok then pass = pass + 1; print("  ok   " .. name)
  else fail = fail + 1; print("  FAIL " .. name .. (detail and ("\n         " .. tostring(detail)) or "")) end
end

local src = io.open("mod/JackieLives/init.lua"):read("a")
local cfg = io.open("mod/JackieLives/config.lua"):read("a")

-- ---------------------------------------------------------------------------
print("\n1. dismissing in person = a walk-off, never a pop")
-- ---------------------------------------------------------------------------
check("the send-off row still runs dismiss_walkaway (not an instant despawn)",
      src:find('action = "dismiss_walkaway"', 1, true) ~= nil)
check("...which tries return-to-post first, then the walk-off",
      src:find("if returnToPost then local ok, res = pcall%(returnToPost%); returned = ok and res == true end") ~= nil)
check("...and names the branch it took in the log",
      src:find('log%("Dismiss: return%-to%-post') ~= nil,
      "both branches fail identically from the pavement; the log is the only way to tell them apart")
check("a dismissal with no resolvable body says so instead of silently doing nothing",
      src:find('log%("Dismiss: NO BODY to walk off') ~= nil)

-- THE BUG. return-to-post must never hand over a body the schedule will delete on the spot.
check("return-to-post clamps its radius to the one the schedule actually honours",
      src:find("math%.min%(%(Config%.transitions and Config%.transitions%.returnRadius%) or 100%.0,\n%s*Config%.proximityRadius or 45%.0%)") ~= nil,
      "unclamped, a dismissal 45-100 m from their venue is an instant clearIdle() — the reported bug")
check("...and says why when it declines",
      src:find("Return%-to%-post declined") ~= nil)

-- pin the two numbers, so raising one alone re-opens the bug
local keep = tonumber(cfg:match("Config%.proximityRadius%s*=%s*([%d%.]+)"))
local ret  = tonumber(cfg:match("returnRadius%s*=%s*([%d%.]+)"))
check("both radii are still declared (keep=" .. tostring(keep) .. ", return=" .. tostring(ret) .. ")",
      keep ~= nil and ret ~= nil)
check("...and scheduleTick is still the one that deletes an out-of-range idle body",
      src:find("clearIdle%(%)%s*%-%- player not nearby") ~= nil,
      "if that despawn moves, re-check the clamp above — it exists to stay on the safe side of it")

-- ---------------------------------------------------------------------------
print("\n2. talking to someone mid-walk-off halts them (JackieLives v1.62 — already native here)")
-- ---------------------------------------------------------------------------
check("opening a conversation PAUSES the retreat",
      src:find("Departure PAUSED") ~= nil)
check("...and turns them to face V (which also cancels the retreat move)",
      src:find("pcall%(jlFaceV%)") ~= nil)
check("jlFaceV exists and rotates in place",
      src:find("function jlFaceV%(handle%)") ~= nil)
check("ending the conversation RESUMES the walk-off",
      src:find("Departure RESUMED") ~= nil)
check("leavingTick neither re-issues nor despawns while paused",
      src:find("if JL%.leaving%.paused then") ~= nil
      and src:find("if Branch and %(Branch%.open or Branch%.busy%) then return end") ~= nil)
check("...with an auto-resume so a missed Branch.finish can't strand them",
      src:find("Departure auto%-resumed") ~= nil)
check("a fresh walk-off never inherits a stale pause",
      src:find("JL%.leaving%.paused = false") ~= nil)
check("an aborted departure drops the pause too",
      src:find("JL%.leaving%.subClearAt, JL%.leaving%.paused = nil, false") ~= nil)

-- ---------------------------------------------------------------------------
print("\n3. nobody spawns naked")
-- ---------------------------------------------------------------------------
check("the outfit is re-asserted after the body exists, not only on the spec",
      src:find("function jlArmAppearanceFix%(h, sp, why%)") ~= nil)
check("...PREFETCH comes BEFORE schedule (the half the spec path never had)",
      (src:find("PrefetchAppearanceChange") or 0) < (src:find("ScheduleAppearanceChange") or 0)
      and src:find("A%.handle:PrefetchAppearanceChange") ~= nil,
      "scheduling a change whose meshes aren't loaded is the race that produces the bare body")
check("...and it VERIFIES with a read-back rather than assuming",
      src:find("GetCurrentAppearanceName") ~= nil)
check("...accepting the .app-level name too (the .ent name contains it)",
      src:find("A%.want:find%(cur, 1, true%)") ~= nil,
      "kerry_eurodyne_kerry_eurodyne_old (template) maps to kerry_eurodyne_old (.app) — both mean success")
check("...and WARNS with both names when it never lands",
      src:find("APPEARANCE NOT APPLIED") ~= nil,
      "an unknown appearance name no-ops silently; this warning is what makes the next report answerable")
check("armed on the COMPANION spawn", src:find('jlArmAppearanceFix%(h, sp, "companion spawn"%)') ~= nil)
check("armed on the IDLE/venue spawn", src:find('jlArmAppearanceFix%(h, sp, "idle spawn"%)') ~= nil)
check("latched, so it cannot re-fire every frame",
      select(2, src:gsub("sp%.appArmed = true", "")) == 2)
check("stepped from onUpdate", src:find('pcall%(jlAppearanceTick%)') ~= nil)

print(("\n%d checks, %d failed"):format(pass + fail, fail))
os.exit(fail == 0 and 0 or 1)
