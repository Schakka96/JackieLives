--[[
  session.lua — SESSION GUARD + CRASH LOG  (v1.59 — real load signal; was v1.52)

  Self-contained module (global `Session`, no top-level `local` in init.lua's main chunk ->
  respects the 200-local cap). Depends on nothing but the game API and a few injected hooks.

  ---------------------------------------------------------------------------
  THE BUG THIS EXISTS TO KILL
  ---------------------------------------------------------------------------
  CET runs `onInit` ONCE PER GAME LAUNCH — *not* per save-load. But `onUpdate` keeps ticking
  straight through a load screen. So every entity handle the mod cached in the previous session
  (JL.summon.spawn.handle, JL.idle.spawn.handle, JL.settle.handle, JL.smile.handle,
  JL.varrival.bikeHandle) survives into the NEXT session, still pointing at an entity whose world
  has been torn down.

  Two consequences, and they are the two symptoms Antonia reported:

  1. CRASH. `onUpdate` dereferences those dead handles every frame (e.g. the companion re-promote
     block: `amm.Spawn:SetNPCAsCompanion(JL.summon.spawn.handle)`). That is a NATIVE dereference of
     freed memory. `pcall` catches Lua errors; it does NOT catch this. Hence a crash that is random
     (depends on whether the memory was reused yet) and unattributable (no Lua traceback).

  2. JACKIE FOLLOWS YOU INTO OTHER SAVES. `companionPersistTick`'s self-heal branch asked "is a live
     companion present?" by dereferencing that same stale handle. Right after a load the handle often
     still resolves, so the mod concluded "he's here!" and wrote the companion fact into the save you
     had just loaded — a save that never had a Jackie. One-way ratchet: once written, it sticks.

  The companion fact itself (`jackielives_companion`) was never the problem — it is a quest fact and
  is correctly per-save. The problem was Lua state outliving the save it belonged to.

  ---------------------------------------------------------------------------
  THE FIX
  ---------------------------------------------------------------------------
  * Detect the session boundary (Session.tick, called FIRST in onUpdate).
  * Bump `Session.id`. Stamp every spawn with the id that created it (`Session.stamp`).
  * A handle whose stamp != the current id is DEAD: drop the reference, NEVER dereference it
    (`Session.stale`). We do not try to despawn it — despawning is itself a dereference.
  * Record whether the companion fact was already true when the session began, so the self-heal can
    never write it into an innocent save (`Session.companionAtStart`).

  ---------------------------------------------------------------------------
  HOW A SESSION BOUNDARY IS DETECTED (and why two signals, not one)
  ---------------------------------------------------------------------------
  RESOLVED v1.59. The v1.52 design guessed that `Game.GetPlayer():GetEntityID().hash` changes on a
  load-from-save. It does NOT: on game 2.31 that hash is the fixed constant 1ULL. jackie_debug.log proved
  it — EVERY load-from-save logged "presence gap, SAME player entity (1ULL) — treating as fast-travel,
  no reset", so the old signal A never fired and this whole guard was inert. That is exactly why Jackie
  kept leaking into innocent saves and crashing the game on load.

  The fix is CDPR's OWN load flag, verified against the redscript dump (game 2.31):

    A (REAL). game_was_loaded — a quest fact. `PlayerPuppet.OnGameAttached` sets it to 1, then a
       1.0 s-delayed `OnGameLoadedFactReset` clears it to 0 (player.script:1245 / :1249). A load-from-save
       re-attaches the player puppet -> fires. A fast-travel only TELEPORTS the existing puppet
       (`TeleportationFacility.TeleportToNode`, fastTravelSystem.script:444) -> never fires. So the fact's
       0->1 rising edge is the authoritative "new session" trigger. We latch the edge because the fact is
       1 for only ~1 s and the player isn't in-world on the exact frame it flips (see M.tick / M.loadPending).

    B. presence gap — the player goes absent and comes back. EVERY load screen has one... but so does
       every fast-travel. So a gap is corroborating evidence, NOT a trigger. If a gap alone reset us, we
       would drop Jackie's handle on every fast-travel and orphan his body. Gaps are logged, never acted on.

  The old playerHash compare is KEPT as a dead-but-harmless belt-and-braces (it can only help if a future
  patch makes the EntityID per-session again). The guard is still self-diagnosing: after one load the log
  now reads "[SESSION] #2 begins — game_was_loaded (native load signal)" when it works.

  ---------------------------------------------------------------------------
  CRASH LOG
  ---------------------------------------------------------------------------
  `log()` in init.lua already opens/appends/closes per line, which is crash-durable — a hard crash
  cannot lose buffered lines. The gap was that onInit TRUNCATED jackie_debug.log on every launch, so
  the log of the run that crashed was destroyed by the run in which you went looking for it.

  Session.rotateLog() moves it to jackie_debug.log.prev first. After a crash, the evidence is in .prev.

  Session.mark(op) writes a breadcrumb immediately before each risky native call and clears it after.
  If the game dies mid-call, the last `[MARK]` line in .prev names the exact operation that killed it.
--]]

local M = {}

M.id               = 0      -- current session generation; 0 = no session seen yet
M.playerHash       = nil    -- last observed player EntityID hash (legacy signal A — dead on 2.31, see below)
M.sawPlayer        = false  -- was the player in-world last tick (signal B)
M.companionAtStart = false  -- companion fact state at session start (guards the self-heal)
M.marker           = nil    -- risky op currently in flight
M.prevLoaded       = nil    -- last observed value of the native `game_was_loaded` fact (edge detect)
M.loadPending      = false  -- latched: a load-from-save fired but the player isn't in-world yet

-- Injected by init.lua so this module never reaches into init's locals.
--   log(msg)              — the existing logger
--   onNewSession(id, why) — init.lua drops its cached handles here
M.bind = function(t)
  M.log          = t.log or function() end
  M.onNewSession = t.onNewSession or function() end
end
M.bind({})

-- ---------------------------------------------------------------------------
-- Crash log
-- ---------------------------------------------------------------------------

-- Preserve the previous run's log before it is truncated. Call ONCE from onInit, BEFORE the first
-- log() of the launch. Without this, a crash erases its own evidence on the next start.
function M.rotateLog()
  pcall(function()
    local src = io.open("jackie_debug.log", "r")
    if not src then return end
    local body = src:read("*a"); src:close()
    if body and #body > 0 then
      local dst = io.open("jackie_debug.log.prev", "w")
      if dst then dst:write(body); dst:close() end
    end
  end)
  pcall(function() local f = io.open("jackie_debug.log", "w"); if f then f:close() end end)
end

-- Breadcrumb around a risky native call. Usage:
--   Session.mark("AMM SetNPCAsCompanion"); <call>; Session.clear()
-- If the game dies inside <call>, the tail of jackie_debug.log.prev names it.
function M.mark(op)
  M.marker = op
  M.log(("[MARK] s%d > %s"):format(M.id, tostring(op)))
end

function M.clear()
  if M.marker then M.log(("[MARK] s%d < %s ok"):format(M.id, tostring(M.marker))) end
  M.marker = nil
end

-- Run fn() wrapped in a breadcrumb. Returns fn's result, or nil if it errored.
-- NOTE: this cannot save you from a native crash — nothing in Lua can. It exists so the LOG says
-- what we were doing when the process died.
function M.guard(op, fn)
  M.mark(op)
  local ok, res = pcall(fn)
  if not ok then M.log(("[MARK] s%d ! %s FAILED: %s"):format(M.id, tostring(op), tostring(res))) end
  M.marker = nil
  return ok and res or nil
end

-- ---------------------------------------------------------------------------
-- Session identity
-- ---------------------------------------------------------------------------

-- The two raw signals. Both must be nil-safe: during a load screen GetPlayer() can be nil, and a
-- player that exists may not yet have a world position.
function M.playerId()
  local h
  local ok = pcall(function()
    local p = Game.GetPlayer(); if not p then return end
    local id = p:GetEntityID(); if not id then return end
    h = tostring(id.hash)
  end)
  return ok and h or nil
end

function M.playerInWorld()
  local pos
  local ok = pcall(function()
    local p = Game.GetPlayer(); if not p then return end
    pos = p:GetWorldPosition()
  end)
  return (ok and pos ~= nil), pos
end

-- THE REAL SIGNAL A (v1.59). CDPR's own load flag. `PlayerPuppet.OnGameAttached` sets the quest fact
-- `game_was_loaded` = 1, then a 1.0 s-delayed `OnGameLoadedFactReset` sets it back to 0
-- (player.script:1245 / :1249, verified against the game-2.31 redscript dump). A fast-travel only
-- TELEPORTS the existing puppet (`TeleportationFacility.TeleportToNode`, fastTravelSystem.script:444) —
-- it never detaches/re-attaches it — so this fact goes to 1 ONLY right after a genuine load-from-save
-- (and on the initial launch into the world), and NEVER on fast-travel. This is exactly the
-- load-vs-fast-travel discriminator the player EntityID hash could never be: on 2.31 that hash is the
-- fixed constant 1ULL (proven in jackie_debug.log — every load logged "SAME player entity (1ULL)"),
-- so the old signal A never fired and this whole guard was inert.
--
-- Returns 0 or 1 (facts default to 0 when unset), or nil only if the QuestsSystem call itself failed.
function M.gameWasLoaded()
  local v
  local ok = pcall(function() v = Game.GetQuestsSystem():GetFactStr("game_was_loaded") end)
  return ok and v or nil
end

-- Stamp a spawn record with the session that created it. Call at every spawn site.
function M.stamp(rec)
  if type(rec) == "table" then rec.spawnSession = M.id end
  return rec
end

-- TRUE if `rec` came from a previous session, i.e. its handle is a dead pointer.
-- The caller must drop the reference WITHOUT dereferencing it. Anything with no stamp is treated as
-- stale: an unstamped record predates this guard, so we cannot prove it is safe.
function M.stale(rec)
  if type(rec) ~= "table" then return false end   -- nothing to be stale
  return rec.spawnSession ~= M.id
end

-- Call FIRST in onUpdate, before any tick that might touch a handle.
-- Returns true on the frame a new session begins.
--
-- ⚠️ WHY THE PRESENCE GAP DOES NOT, BY ITSELF, START A NEW SESSION
-- A fast-travel also blanks the player for a few frames. If a gap alone triggered a reset we would drop
-- Jackie's handle on every fast-travel and orphan his body — and with Config.persist disabled nothing
-- would bring him back. So the gap is NOT the trigger.
--
-- The discriminator is CDPR's native `game_was_loaded` fact (real signal A): a load-from-save re-attaches
-- the player puppet and sets it to 1 for ~1 s; a fast-travel only teleports the puppet and never sets it.
-- Signal B (presence gap) is only corroborating evidence, logged so we can tell the two transitions apart.
-- (The old player-hash compare is dead on 2.31 — the hash is the constant 1ULL — and is kept only as a
-- harmless fallback; see the module header for the full diagnosis.)
function M.tick()
  local hash    = M.playerId()
  local inWorld = M.playerInWorld()
  local loaded  = M.gameWasLoaded()

  -- Rising edge of the native load fact = a genuine load-from-save just began. LATCH it: the fact stays
  -- 1 for ~1 s (dozens of frames) and the player is usually NOT yet in-world on the exact frame it flips,
  -- so we remember it and act once he appears. Fast-travel never trips this (it doesn't re-attach).
  if loaded == 1 and M.prevLoaded ~= 1 then
    M.loadPending = true
    M.log("[SESSION] game_was_loaded 0->1 — load-from-save detected (native signal); waiting for world.")
  end
  M.prevLoaded = loaded

  -- Player absent: mid-load or mid-fast-travel. Remember the gap; keep the latch; decide nothing yet.
  if not inWorld then
    M.sawPlayer = false
    return false
  end

  local gap = not M.sawPlayer                                    -- signal B: came back from an absence
  local why = nil
  if M.id == 0 then
    why = "first session"                                        -- launch / first world entry
  elseif M.loadPending then                                      -- REAL signal A: CDPR's own load flag fired
    why = "game_was_loaded (native load signal)" .. (gap and " after a load screen" or "")
  elseif hash and M.playerHash and hash ~= M.playerHash then     -- legacy signal A: player entity rebuilt
    -- Dead on 2.31 (hash is the constant 1ULL) — kept as a harmless belt-and-braces in case a future
    -- patch makes the EntityID per-session again.
    why = ("player entity changed (%s -> %s)%s"):format(
            tostring(M.playerHash), tostring(hash), gap and " after a load screen" or "")
  end

  -- A gap with NO load fact and the SAME player entity = fast-travel / district stream. Do NOT reset:
  -- dropping handles here is what would orphan Jackie on every fast-travel. Log it so the two cases
  -- stay distinguishable in jackie_debug.log.
  if gap and not why then
    M.log(("[SESSION] presence gap, SAME player entity (%s), no load fact — fast-travel, no reset.")
            :format(tostring(hash)))
  end

  M.playerHash  = hash or M.playerHash
  M.sawPlayer   = true
  M.loadPending = false                                          -- consume the latch (whether or not it fired)
  if not why then return false end

  M.id = M.id + 1
  M.log(("[SESSION] #%d begins — %s"):format(M.id, why))

  -- Record the companion fact BEFORE anything can self-heal it. This is what stops Jackie leaking
  -- into a save that never had him.
  local v
  pcall(function() v = Game.GetQuestsSystem():GetFactStr("jackielives_companion") end)
  M.companionAtStart = (v == 1)
  M.log(("[SESSION] #%d companion fact at start = %s"):format(M.id, tostring(M.companionAtStart)))

  -- Hand off: init.lua drops its cached handles. It must NOT dereference or despawn them.
  pcall(function() M.onNewSession(M.id, why) end)
  return true
end

-- Header for a fresh log. Called from onInit after rotateLog().
function M.header(mode)
  local stamp = "?"
  pcall(function() stamp = os.date("%Y-%m-%d %H:%M:%S") end)
  M.log("=================================================================")
  M.log(("[SESSION] launch %s | mode=%s"):format(stamp, tostring(mode)))
  M.log("[SESSION] previous run's log preserved as jackie_debug.log.prev")
  M.log("=================================================================")
end

return M
