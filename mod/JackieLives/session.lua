--[[
  session.lua — SESSION GUARD + CRASH LOG  (v1.49)

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
  UNVERIFIED against the redscript dump (not available on the Mac; see the `cp2077-redscript-dump-source`
  note). Two signals, with different jobs:

    A. playerHash — `Game.GetPlayer():GetEntityID().hash`. A load-from-save REBUILDS the player puppet;
       a fast-travel only teleports the existing one. So a hash change means "new session". AUTHORITATIVE:
       this and only this triggers the reset.

    B. presence gap — the player goes absent and comes back. EVERY load screen has one... but so does
       every fast-travel. So a gap is corroborating evidence, NOT a trigger. If a gap alone reset us, we
       would drop Jackie's handle on every fast-travel and orphan his body — and with Config.persist
       disabled, nothing would spawn him back. Gaps are logged, never acted on.

  THE OPEN RISK, STATED PLAINLY: if the player's EntityID is a fixed well-known constant rather than a
  per-session runtime id, signal A never fires and this guard never triggers. The design is deliberately
  self-diagnosing — after one load-from-save the log reads either

      [SESSION] #2 begins — player entity changed (...)        <- guard works
      [SESSION] presence gap, SAME player entity (...)          <- guard never fires; needs a real hook

  so ONE in-game load tells us the answer instead of us guessing. If it's the second line, the fix is an
  observed load event (PlayerPuppet.OnGameAttached), which needs the dump to verify.

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
M.playerHash       = nil    -- last observed player EntityID hash (signal A)
M.sawPlayer        = false  -- was the player in-world last tick (signal B)
M.companionAtStart = false  -- companion fact state at session start (guards the self-heal)
M.marker           = nil    -- risky op currently in flight

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
-- The discriminator is the player ENTITY: a load-from-save rebuilds the player puppet, a fast-travel only
-- teleports the existing one. Hence signal A (hash change) is authoritative and signal B (gap) is only
-- corroborating evidence, logged so we can tell the two transitions apart.
--
-- ⚠️ THE OPEN RISK, STATED PLAINLY: if the player's EntityID turns out to be a fixed well-known constant
-- rather than a per-session runtime id, signal A never fires and this guard never triggers. That is
-- UNVERIFIED (no redscript dump on the Mac). It is also *self-diagnosing*: on the first load-from-save the
-- log will show either "[SESSION] #2 begins" (works) or "presence gap, SAME player entity" (doesn't). Read
-- jackie_debug.log after one load and we will know, instead of guessing.
function M.tick()
  local hash    = M.playerId()
  local inWorld = M.playerInWorld()

  -- Player absent: mid-load or mid-fast-travel. Remember the gap; decide nothing yet.
  if not inWorld then
    M.sawPlayer = false
    return false
  end

  local gap = not M.sawPlayer                                    -- signal B: came back from an absence
  local why = nil
  if M.id == 0 then
    why = "first session"                                        -- launch / first world entry
  elseif hash and M.playerHash and hash ~= M.playerHash then     -- signal A: the player entity was rebuilt
    why = ("player entity changed (%s -> %s)%s"):format(
            tostring(M.playerHash), tostring(hash), gap and " after a load screen" or "")
  end

  -- A gap with the SAME player entity = fast-travel / district stream. Do NOT reset: dropping handles
  -- here is what would orphan Jackie on every fast-travel. Log it so the two cases stay distinguishable.
  if gap and not why then
    M.log(("[SESSION] presence gap, SAME player entity (%s) — treating as fast-travel, no reset.")
            :format(tostring(hash)))
  end

  M.playerHash = hash or M.playerHash
  M.sawPlayer  = true
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
