-- nca.lua — OPTIONAL integration with Night City Allies (global `Allies`)
-- =============================================================================
-- ⚠️ READ docs/research/nca_integration.md BEFORE CHANGING ANY OF THIS.
--
-- WHAT THIS FIXES. Both mods `Override("InteractionUIBase", "OnDialogsData")`. NCA APPENDS its hub
-- to data.choiceHubs and then calls wrapped(). We RETURN WITHOUT CALLING wrapped while our own box
-- is shown — deliberately, because the game emits empty DialogChoiceHubs pushes constantly and
-- letting them through sets m_AreDialogsOpen = false and hides our box mid-conversation. Their
-- override lives inside that wrapped, so while we are talking it never runs and their menu — hire,
-- follow, wait, equipment, outfit, send away — silently disappears. A user reported exactly that.
--
-- The fix is not to stop swallowing (that trades their bug for ours). It is to STOP COMPETING FOR
-- THE WIDGET AT ALL when NCA owns the character: we add one row to THEIR menu and render our
-- conversation through THEIR renderer. One menu, their commands, our writing.
--
-- ⚠️ THEIRS IS NOT A WORSE VERSION OF OURS. Their menu is COMMANDS (verbs: follow, wait, equip,
-- dismiss). Ours is CONVERSATION (words). Replacing theirs costs the player real functionality, so
-- "which dialogue is better" was always the wrong question. They compose.
--
-- HOW WE ATTACH (no cooperation from them required, and no file written into their folder):
--   their init.lua ends `return NCA:new(app)` and sets `NCA.app = app`, so from our sandbox
--   GetMod("NightCityAllies").app reaches
--     .availableInteractions  the table their menu renders (Application/app.lua:59)
--     .ui:choice(title, rows) their renderer — nestable; their own 030_social.lua recurses through it
--   We append one row shaped exactly like the ones their Interactions/*.lua return.
--
-- ⚠️ `app` IS REACHABLE, NOT PUBLISHED. It works because Lua tables are open, not because they
-- documented it. Therefore: every single call into their objects is pcall'd, any failure detaches us
-- and falls back to our own DialogUI, and the version we attached to is logged. If they ever add a
-- real RegisterInteraction hook, switch to it and delete `attach()` — nothing else here changes.
--
-- ENTIRELY OPTIONAL. `GetMod("NightCityAllies")` returning nil is the normal case and is not an
-- error path: we simply never attach, and the mod behaves exactly as it did before this file.
-- =============================================================================

local M = { version = "1.0" }

local S = {
  attached  = false,
  row       = nil,       -- the exact table we inserted, so detach() removes OURS and nothing else
  app       = nil,
  modVer    = nil,
  tries     = 0,
  nextTry   = 0,
  talking   = false,     -- a conversation is running through THEIR ui right now
  node      = nil,
  tree      = nil,
  taken     = nil,       -- `once` ledger for this conversation (mirrors Branch's bstate.taken)
}

M.env = {}

-- Bound from init.lua. Everything this module needs from the engine arrives here, because the
-- engine's conversation runner is built out of file-locals (speakCompanionLine, pickPoolLine) that a
-- separate module cannot reach. Same pattern as NCL.bind / DialogUI.bind / Msg.env.
-- ⚠️ Like NCL.bind, this copies only the keys it NAMES. Passing a binding without listing it here
-- drops it silently, and the offline test won't catch it because it assigns M.env directly.
function M.bind(t)
  for _, k in ipairs({
    "log",          -- function(msg)
    "speak",        -- function(text, sfx, mute) -> seconds   (the companion says a line)
    "sayPlayer",    -- function(text)                          (V's chosen line, as a subtitle)
    "pickLine",     -- function(pool) -> entry                 (rarity-aware pool pick)
    "var",          -- function(entry) -> entry                (male-V / Hermano swap)
    "talkTree",     -- function() -> the active persona's talk tree
    "personaName",  -- function() -> "Lucy"
    "activeKey",    -- function() -> "lucy"
    "recordIsOurs", -- function(recordOrName) -> bool
    "famAllows",    -- function(minFam) -> bool
    "famAdd",       -- function(award)
    "endHook",      -- function()  called when the conversation closes (clears prompts etc.)
  }) do if t[k] ~= nil then M.env[k] = t[k] end end
end

local function log(m) if M.env.log then pcall(M.env.log, "[NCA] " .. tostring(m)) end end

function M.present() return S.attached end
function M.talking() return S.talking end

-- ---------------------------------------------------------------------------
-- Is this NCA npc the character WE write for?
-- ---------------------------------------------------------------------------
-- ⚠️ THIS GATE IS THE WHOLE SAFETY STORY. Our row must appear on our persona and on nobody else —
-- NCA users hire all sorts of people, and a "Talk" row that opened Lucy's tree on a random mercenary
-- would be worse than no integration at all. Two signals, strongest first:
--   1. the entity's RECORD, asked through nclRecordIsOurs (the same predicate the rest of the engine
--      uses, so it follows the active persona and the v1.1 TweakXL record automatically);
--   2. the DISPLAY NAME, as a fallback for when the entity can't be resolved from its id.
-- A failure to determine either answers NO. Silence is the safe default here.
function M.isOurs(npc)
  if not npc then return false end
  local ok = false

  pcall(function()
    local id = npc:GetEntityID()
    local ent = id and Game.FindEntityByID(id)
    local rec = ent and ent:GetRecordID()
    if rec and M.env.recordIsOurs then ok = M.env.recordIsOurs(tostring(rec.value or rec)) and true or false end
  end)
  if ok then return true end

  pcall(function()
    local nm = npc:GetName()
    local mine = M.env.personaName and M.env.personaName()
    if nm and mine and nm ~= "" and mine ~= "" then
      ok = (tostring(nm):lower():find(tostring(mine):lower(), 1, true) ~= nil)
    end
  end)
  return ok
end

-- ---------------------------------------------------------------------------
-- Build the rows for one node of our tree, in THEIR row format.
-- ---------------------------------------------------------------------------
-- Honours the gating a pack author expects: `cond`, `minFam`, `chance`, `once`, and `textPool`.
--
-- ⚠️ DELIBERATELY NOT HONOURED: the node-level `pick = N` sampler. In our own box a hub shows only
-- 3-5 of its topics because the box is a fixed-height list; NCA's renderer PAGINATES (Application/
-- ui.lua MAX_CHOICES_PER_PAGE), so the reason for sampling doesn't exist there and sampling would
-- just hide writing behind a "next page" the player can already use. The familiarity GATES still
-- apply, so nothing arrives early — this only changes how much of what she's willing to say is
-- visible at once.
local function rowsFor(node)
  local rows = {}
  for _, c in ipairs((node and node.choices) or {}) do
    local show = true
    if c.cond then local o, r = pcall(c.cond); show = (o and r ~= false) end
    if show and c.minFam and M.env.famAllows then
      local o, r = pcall(M.env.famAllows, c.minFam); show = (o and r ~= false)
    end
    if show and c.chance then
      local r = 1.0; pcall(function() r = math.random() end); show = (r < c.chance)
    end
    if show and c.once and S.taken and S.taken[c.once] then show = false end
    if show then
      local label = c.text
      if c.textPool and #c.textPool > 0 and M.env.pickLine then
        local o, e = pcall(M.env.pickLine, c.textPool)
        if o and e and e.text then label = e.text end
      end
      if label and label ~= "" then rows[#rows + 1] = { choice = c, label = tostring(label) } end
    end
  end
  return rows
end

-- ---------------------------------------------------------------------------
-- Render one node through THEIR ui, and wire each row to advance our tree.
-- ---------------------------------------------------------------------------
local function renderNode(npc, ui, nodeKey)
  local tree = S.tree
  local node = tree and tree.nodes and tree.nodes[nodeKey or tree.start]
  if not node then M.stop(); return end
  S.node = node

  -- her line for this node (single line, pool, or a silent hub)
  local line = node.companion
  if node.companionPool and #node.companionPool > 0 and M.env.pickLine then
    local o, e = pcall(M.env.pickLine, node.companionPool); if o then line = e end
  end
  if M.env.var and line then local o, e = pcall(M.env.var, line); if o and e then line = e end end
  if line and line.text and line.text ~= "" and not node.silent and M.env.speak then
    -- ⚠️ We speak and then open the rows IMMEDIATELY, rather than waiting out the line the way our
    -- own runner does (Branch.start arms bstate.openAt). Their hub is opened by us from inside a
    -- callback, and there is no tick of theirs we could defer it to without leaving the player
    -- staring at nothing. The subtitle stays up underneath the menu, which reads fine.
    pcall(M.env.speak, line.text, line.sfx, tree.muteFallback)
  end

  local rows = rowsFor(node)
  if #rows == 0 then M.stop(); return end

  local entries = {}
  for _, r in ipairs(rows) do
    entries[#entries + 1] = {
      label = r.label,
      callback = function()
        local c = r.choice
        if c.once then S.taken = S.taken or {}; S.taken[c.once] = true end
        if c.fam and M.env.famAdd then pcall(M.env.famAdd, c.fam) end
        if M.env.sayPlayer and c.text then pcall(M.env.sayPlayer, tostring(c.text)) end
        if c.to then
          -- re-enter their renderer for the next node, exactly as their own 030_social.lua nests
          renderNode(npc, ui, c.to)
        else
          M.stop()
        end
      end,
    }
  end

  local title = (M.env.personaName and M.env.personaName()) or "Talk"
  local ok = pcall(function() ui:choice(title, entries) end)
  if not ok then log("their ui:choice threw — ending and falling back"); M.stop() end
end

function M.stop()
  S.talking, S.node, S.tree, S.taken = false, nil, nil, nil
  if M.env.endHook then pcall(M.env.endHook) end
end

-- ---------------------------------------------------------------------------
-- The row we add to their menu.
-- ---------------------------------------------------------------------------
function M.buildRow()
  return {
    label = "Talk",
    condition = function(npc)
      local ok, r = pcall(M.isOurs, npc)
      return ok and r or false
    end,
    callback = function(npc, ui)
      local tree = M.env.talkTree and M.env.talkTree()
      if not tree or not tree.nodes then log("no talk tree for the active persona"); return end
      S.talking, S.tree, S.taken = true, tree, {}
      renderNode(npc, ui, tree.start)
    end,
  }
end

-- ---------------------------------------------------------------------------
-- Attach / detach
-- ---------------------------------------------------------------------------
function M.attach(mod)
  if S.attached then return true end
  local app
  pcall(function() app = mod and mod.app end)
  if not app then return false end

  local list
  pcall(function() list = app.availableInteractions end)
  if type(list) ~= "table" then
    log("their app has no availableInteractions table — not attaching (their layout changed)")
    return false
  end

  -- Idempotent: a CET hot-reload runs onInit again, and appending twice would show two Talk rows.
  for _, e in ipairs(list) do
    if type(e) == "table" and e.__jackielives then
      S.row, S.app, S.attached = e, app, true
      return true
    end
  end

  local row = M.buildRow()
  row.__jackielives = true                     -- our marker, so detach removes OURS and nothing else
  local ok = pcall(function() table.insert(list, row) end)
  if not ok then log("could not insert our row"); return false end

  S.row, S.app, S.attached = row, app, true
  pcall(function() S.modVer = mod.version or mod.VERSION end)
  log(("attached to Night City Allies%s — 'Talk' added to their menu for %s")
      :format(S.modVer and (" v" .. tostring(S.modVer)) or "",
              (M.env.personaName and M.env.personaName()) or "the active companion"))
  return true
end

function M.detach()
  if not S.attached then return end
  pcall(function()
    local list = S.app and S.app.availableInteractions
    if type(list) == "table" then
      for i = #list, 1, -1 do
        if list[i] == S.row then table.remove(list, i) end
      end
    end
  end)
  S.attached, S.row, S.app = false, nil, nil
  M.stop()
  log("detached")
end

-- ---------------------------------------------------------------------------
-- tick — find them, once, without spinning
-- ---------------------------------------------------------------------------
-- ⚠️ NOT AT onInit. CET loads mods in an order we do not control, so GetMod("NightCityAllies") is
-- very often nil at our onInit and non-nil a second later. We retry on a slow timer for a short
-- while and then stop for good: a player without NCA must not pay a GetMod call forever.
M.maxTries      = 20
M.retrySeconds  = 3.0

function M.tick(now)
  if S.attached or S.tries >= M.maxTries then return end
  now = now or 0
  if now < S.nextTry then return end
  S.nextTry = now + M.retrySeconds
  S.tries = S.tries + 1

  local mod
  pcall(function() mod = GetMod("NightCityAllies") end)
  if not mod then
    if S.tries == M.maxTries then log("Night City Allies not installed — integration off (this is normal)") end
    return
  end
  M.attach(mod)
end

return M
