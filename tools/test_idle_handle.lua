-- tools/test_idle_handle.lua — the v1.8.8 regression: the VENUE body has to resolve its handle.
--
-- Run from the repo root:   luajit tools/test_idle_handle.lua mod/JackieLives/init.lua
-- Exits non-zero on failure. Stock Lua 5.x, no game, no CET.
--
-- THE BUG IT PINS (reported 2026-08-21: "Jackie doesn't spawn at Misty's or The Afterlife during his
-- scheduled times"). Since v1.68 the default spawn backend is NATIVE, and Native.spawn returns
-- `{ id = <EntityID>, handle = nil }` — the handle resolves a frame or two later via
-- Game.FindEntityByID. `resolveJackieHandle()` does that resolving, but it only ever looks at
-- `JL.summon.spawn`, the COMPANION body. NOTHING in the mod ever wrote `JL.idle.spawn.handle`.
--
-- So every reader of the venue body saw nil forever. wanderTick returned at its first line, and
-- wanderTick's placement step is the ONLY thing that teleports the body onto a venue waypoint —
-- ammSpawn(0, ...) passes no position at all, so Native.spawn falls back to inFrontOfPlayer(1 m).
-- The venue Jackie was being created one metre in front of V and left standing in the street.
--
-- This is the v1.68 native-spawn trap a second time, on the path nobody re-checked. The test is
-- deliberately about the RESOLVER, not about wanderTick: wanderTick is a file-local and its body is
-- 200 lines of ImGui-free but engine-heavy placement code. The resolver is the whole fix.

local SRC = arg[1] or "mod/JackieLives/init.lua"
local srcf = assert(io.open(SRC, "r"), "cannot read " .. SRC .. " — run this from the repo root")
local src = srcf:read("a"); srcf:close()

local fails = 0
local function check(name, cond, extra)
  print((cond and "ok   " or "FAIL ") .. name .. (extra and ("   " .. tostring(extra)) or ""))
  if not cond then fails = fails + 1 end
end

-- ---------------------------------------------------------------------------
-- 1. THE STATIC HALF — wanderTick must not read the raw field again
-- ---------------------------------------------------------------------------
-- If someone "simplifies" the resolver call back to `sp and sp.handle`, every check below still
-- passes (the resolver would still exist, just unused) and the bug returns silently. So pin the
-- call site too.
print("1. wanderTick resolves rather than reading the raw field")
local wt = src:match("\nlocal function wanderTick%(%)(.-)\n  local loc = Config%.locations%[JL%.idle%.locationKey%]")
check("wanderTick found (renamed? then fix this harness)", wt ~= nil)
if wt then
  check("...it calls the resolver", wt:find("jlResolveIdleHandle", 1, true) ~= nil,
        "it went back to reading JL.idle.spawn.handle directly — the venue body is never placed")
end

-- ---------------------------------------------------------------------------
-- 2. THE LIVE HALF — run the real resolver against a native-shaped spawn record
-- ---------------------------------------------------------------------------
print("\n2. the resolver fills a native spawn record's handle")
local s = src:find("\nfunction jlResolveIdleHandle%(")
if not s then
  check("jlResolveIdleHandle exists", false, "the fix is gone")
else
  local e = src:find("\nend\n", s)
  local body = src:sub(s + 1, e + 4)

  local BODY = { id = "the-entity" }
  local found = nil                      -- what FindEntityByID currently answers
  JL = { clock = 0, idle = { spawn = nil, locationKey = "misty", spawnedAt = 0 } }
  Game = { FindEntityByID = function(id) return (id == "eid-1") and found or nil end }
  local logged = {}
  function log(m) logged[#logged + 1] = tostring(m) end
  load(body)()

  check("no spawn record -> nil, and no crash", jlResolveIdleHandle() == nil)

  -- The frames right after CreateEntity: the id exists, the entity does not yet.
  JL.idle.spawn = { id = "eid-1", handle = nil, native = true }
  check("not resolvable yet -> nil", jlResolveIdleHandle() == nil)
  check("...and it has not warned yet (only 0 s in)", #logged == 0)

  -- ...and now the entity streams in. THIS is the assignment that never existed.
  found = BODY
  local h = jlResolveIdleHandle()
  check("the entity exists -> the resolver returns it", h == BODY)
  check("...and CACHES it on the spawn record", JL.idle.spawn.handle == BODY,
        "every other reader of JL.idle.spawn.handle depends on this write")

  local said = table.concat(logged, "|")
  check("...and says so once", said:find("Idle body resolved", 1, true) ~= nil, said)
  local before = #logged
  jlResolveIdleHandle(); jlResolveIdleHandle()
  check("...exactly once, not once per frame", #logged == before)

  -- An AMM-backend record already carries its handle; the resolver must not disturb it.
  JL.idle.spawn = { handle = "amm-body" }
  check("an AMM record's handle is returned untouched", jlResolveIdleHandle() == "amm-body")

  -- A body that never streams in has to become visible in the log — that silence is how this
  -- survived from v1.68 to v1.8.8.
  logged = {}
  found = nil
  JL.idle.spawn = { id = "eid-missing", handle = nil }
  JL.idle.spawnedAt, JL.clock = 0, 6.0
  jlResolveIdleHandle()
  said = table.concat(logged, "|")
  check("a body that never resolves warns after 5 s", said:find("never resolved", 1, true) ~= nil, said)
  before = #logged
  jlResolveIdleHandle()
  check("...and warns once, not every frame", #logged == before)
end

print("")
if fails > 0 then print(fails .. " FAILED"); os.exit(1) end
print("ALL PASS")
