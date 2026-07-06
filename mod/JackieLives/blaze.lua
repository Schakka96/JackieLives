--[[
  blaze.lua — "Blaze of Glory" HEIST SET-PIECE  (v0.96, MVP-A)
  ============================================================================
  Self-contained module (global `Blaze`, NO top-level local -> respects init.lua's
  200-local cap, exactly like retrieval.lua). init.lua couples to it in a few
  one-line spots (require, bind, onUpdate tick, onDraw UI) and injects EVERY
  game-touching primitive via Blaze.bind{} — so this file never calls a game API
  directly and any unbound helper simply no-ops (the set-piece degrades, never
  crashes). Pure Lua in here; all the CET/Game calls live in init.lua's bind block.

  THE SET-PIECE (alternate-timeline route; only runs while JL.mode == "blaze"):
    Konpeki Plaza suite, played as a STANDALONE what-if — NOT wired into the live
    Heist quest, so there's no lockdown / blocked-stairs geometry to fight. We spawn:
      - Goro Takemura  at the elevator   (hostile)
      - Adam Smasher   on the balcony    (hostile — the real threat)
      - a hovering VTOL just off the balcony edge (the extraction ride)
    Objectives:
      1  Kill Adam Smasher  (+ optional: Kill Goro Takemura)
      2  [unlocks the instant Smasher dies]  Reach the extraction VTOL
      3  V within `reachRadius` of the VTOL -> CUT TO BLACK (cutscene stand-in)

    MVP-A drives a PLACEHOLDER on-screen objective (the native message band, via the
    injected `objective()` helper). MVP-B swaps `objective()` + `fade()` for real
    WolvenKit .journal objectives + a real scene — see
    docs/BLAZE_WOLVENKIT_OBJECTIVES.md. That swap is one-line-per-helper in init.lua.

  All positions + records are captured/verified IN-GAME on Windows (Mac can't run
  the game). Use the overlay's "Capture ... spot" and "Grab ... record" buttons,
  then paste the console-logged values into M.cfg below to make them permanent.
--]]

local M = { bound = {}, cfg = nil, st = nil }

-- ---- CONFIG (fill after in-game capture on Windows) -----------------------
M.cfg = {
  -- TweakDB Character records to spawn. Leave as-is until you grab the real ones:
  -- spawn Smasher/Takemura ONCE via AMM's own menu, then click the overlay's
  -- "Grab ... record" button (it reads AMM's spawned list and logs the exact path).
  smasherRecord = "Character.Smasher",   -- confirmed via AMM (Antonia 2026-07-07)
  goroRecord    = "Character.Takemura",  -- confirmed via AMM (Antonia 2026-07-07)
  -- Heli = a VEHICLE record (AMM menu name "Arasaka Helicopter"). It's NOT in AMM's NPC list,
  -- so grab it with the overlay's "Grab heli record (look at it)" button, then it auto-saves.
  heliRecord    = nil,   -- e.g. "Vehicle.av_..."   (look-at grab fills this)

  -- Spawn transforms {x,y,z,yaw}. Capture on Windows: stand on the spot, FACE the
  -- way the NPC/heli should look, click the matching "Capture ... spot" button.
  smasherPos = nil,      -- balcony
  goroPos    = nil,      -- elevator
  heliPos    = nil,      -- hovering just off the balcony edge (elevated Z)

  reachRadius       = 6.0,   -- metres from the VTOL that triggers the escape cut
  gateOnSmasherOnly = true,  -- escape unlocks when SMASHER dies (Takemura optional), per design
}

-- ---------------------------------------------------------------------------
-- Wiring
-- ---------------------------------------------------------------------------
function M.bind(t)
  for k, v in pairs(t or {}) do M.bound[k] = v end
end

local function blog(msg)
  if M.bound.log then M.bound.log("[Blaze] " .. tostring(msg)) end
end

-- Push objective text to screen only when it CHANGES (so we don't spam the native
-- message band every frame). MVP-A: this is the injected `objective()` (message band).
-- MVP-B: point `objective()` at JournalManager and this same call drives real objectives.
local function pushObjective(text)
  local st = M.st; if not st then return end
  if text == st.lastObjective then return end
  st.lastObjective = text
  if M.bound.objective then M.bound.objective(text, 8.0) end
end

-- ---- config setters used by the overlay -----------------------------------
function M.setRecord(slot, str)  -- slot: "smasher" | "goro" | "heli"
  M.cfg[slot .. "Record"] = str
  blog(slot .. " record set = " .. tostring(str))
  if M.bound.persist then M.bound.persist() end   -- auto-write blaze_config.txt (no console copying)
end

function M.setPos(slot, p)       -- slot: "smasher" | "goro" | "heli"; p = {x,y,z,yaw}
  if not p then return end
  M.cfg[slot .. "Pos"] = p
  blog(string.format("%s pos set = { x=%.2f, y=%.2f, z=%.2f, yaw=%.1f }", slot, p.x, p.y, p.z, p.yaw or 0.0))
  if M.bound.persist then M.bound.persist() end   -- auto-write blaze_config.txt (no console copying)
end

function M.hasPositions() local c = M.cfg; return (c.goroPos and c.smasherPos and c.heliPos) and true or false end
function M.hasRecords()   local c = M.cfg; return (c.goroRecord and c.smasherRecord and c.heliRecord) and true or false end

-- ---------------------------------------------------------------------------
-- Run / stop
-- ---------------------------------------------------------------------------
local function spawnOne(slot, rec, pos, hostile)
  if not (M.bound.spawnDyn and rec and pos) then blog("skip spawn " .. slot .. " (missing spawnDyn/record/pos)"); return end
  local id = M.bound.spawnDyn(rec, pos, pos.yaw, "JackieLives_blaze_" .. slot)
  M.st.ent[slot] = { id = id, pos = pos, yaw = pos.yaw, hostile = hostile, handle = nil, placed = false }
  blog(slot .. " spawn id=" .. tostring(id) .. " rec=" .. tostring(rec))
end

function M.start()
  if not M.hasRecords() then
    blog("Cannot start: grab all 3 records first (Smasher / Takemura / heli).")
    if M.bound.objective then M.bound.objective("Blaze: grab the 3 spawn records first (see overlay).", 6.0) end
    return false
  end
  if not M.hasPositions() then
    blog("Cannot start: capture all 3 positions first (elevator / balcony / hover).")
    if M.bound.objective then M.bound.objective("Blaze: capture the 3 spawn positions first (see overlay).", 6.0) end
    return false
  end
  M.reset()
  M.st = { active = true, stage = "fight", ent = {}, smasherDead = false, goroDead = false,
           lastObjective = "", firedFade = false }
  local c = M.cfg
  spawnOne("goro",    c.goroRecord,    c.goroPos,    true)
  spawnOne("smasher", c.smasherRecord, c.smasherPos, true)
  spawnOne("heli",    c.heliRecord,    c.heliPos,    false)
  pushObjective("[ ] Kill Adam Smasher\n[ ] Kill Goro Takemura")
  blog("Set-piece STARTED.")
  return true
end

function M.reset()
  if M.st and M.st.ent then
    for slot, e in pairs(M.st.ent) do
      if e.id and M.bound.deleteById then M.bound.deleteById(e.id); blog("despawned " .. slot) end
    end
  end
  M.st = nil
end

function M.status()
  local c = M.cfg
  local rec = (c.goroRecord and "G" or "g") .. (c.smasherRecord and "S" or "s") .. (c.heliRecord and "H" or "h")
  local pos = (c.goroPos and "G" or "g") .. (c.smasherPos and "S" or "s") .. (c.heliPos and "H" or "h")
  if not M.st or not M.st.active then
    return "idle   records[" .. rec .. "]  positions[" .. pos .. "]"
  end
  return "RUNNING   stage=" .. tostring(M.st.stage) .. "   smasherDead=" .. tostring(M.st.smasherDead) ..
         "   goroDead=" .. tostring(M.st.goroDead)
end

-- Fire the alternate-timeline world unlock on demand (overlay TEST button), so we can validate the
-- fact lever without running the whole set-piece. Same helper the `cut` stage calls. No-op if unbound.
function M.testWorldUnlock()
  if M.bound.worldUnlock then M.bound.worldUnlock(); return true end
  blog("worldUnlock helper not bound.")
  return false
end

-- ---------------------------------------------------------------------------
-- Per-frame state machine (stepped from init.lua onUpdate while mode == "blaze")
-- ---------------------------------------------------------------------------
-- Resolve an entity's handle once (a few frames after DES spawn), then place it
-- on its captured transform and (if hostile) turn it against V. Done ONCE per
-- entity: we must NOT re-teleport an NPC every frame or it can't move to fight.
local function resolveAndPlace(e)
  if not e or e.placed then return end
  if not e.handle and M.bound.findEntity and e.id then e.handle = M.bound.findEntity(e.id) end
  if not e.handle then return end                       -- not streamed in yet; try again next frame
  if M.bound.teleport and e.pos then M.bound.teleport(e.handle, e.pos, e.yaw) end
  if e.hostile and M.bound.setHostile then M.bound.setHostile(e.handle) end
  e.placed = true
end

local function isDead(e)
  if not (e and e.placed) then return false end          -- don't count "not yet spawned" as dead
  if not M.bound.isDead then return false end
  return M.bound.isDead(e.handle) and true or false
end

function M.tick(now, dt)
  local st = M.st; if not st or not st.active then return end

  for _, slot in ipairs({ "goro", "smasher", "heli" }) do
    resolveAndPlace(st.ent[slot])
  end

  if not st.smasherDead and isDead(st.ent.smasher) then st.smasherDead = true; blog("Adam Smasher is DOWN.") end
  if not st.goroDead    and isDead(st.ent.goro)    then st.goroDead    = true; blog("Goro Takemura is DOWN.") end

  if st.stage == "fight" then
    local s = st.smasherDead and "[x]" or "[ ]"
    local g = st.goroDead    and "[x]" or "[ ]"
    pushObjective(s .. " Kill Adam Smasher\n" .. g .. " Kill Goro Takemura")
    local gate = M.cfg.gateOnSmasherOnly and st.smasherDead or (st.smasherDead and st.goroDead)
    if gate then
      st.stage = "escape"
      pushObjective("[x] Smasher down\n>> GET TO THE VTOL — reach the extraction chopper")
    end

  elseif st.stage == "escape" then
    local d = (M.bound.distToPlayer and M.cfg.heliPos) and M.bound.distToPlayer(M.cfg.heliPos) or 1e9
    if d <= (M.cfg.reachRadius or 6.0) then st.stage = "cut" end

  elseif st.stage == "cut" then
    if not st.firedFade then
      st.firedFade = true
      blog("CUTSCENE TRIGGER: Smasher dead + V reached the VTOL.")
      -- Alternate-timeline payoff: lift the Watson prologue lockdown so the world opens WITHOUT the
      -- Heist's death/q101 tail (the placed barrier reads the fact `watson_prolog_unlock` directly;
      -- vanilla only sets it deep inside q101 / Love Like Fire). Because this what-if never completes
      -- the real q005, q101 never starts -> no Johnny, no biochip, no death. Idempotent; no-ops if
      -- the helper isn't bound. See docs/research/q005_graph_findings.md.
      if M.bound.worldUnlock then M.bound.worldUnlock() end
      if M.bound.fade then M.bound.fade("BLAZE OF GLORY — you and Jackie make the jump. (cut to black)") end
    end
    st.stage = "done"
  end
end

return M
