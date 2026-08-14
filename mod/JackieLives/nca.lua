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
  draw      = nil,       -- sticky hub draws, keyed by node (mirrors NCS.hubDraw)
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
    "now",          -- function() -> seconds (engine clock; drives the sticky hub draw)
    "hubRefresh",   -- function() -> lo, hi   (Config.dialogue.hubRefreshMin/Max)
  }) do if t[k] ~= nil then M.env[k] = t[k] end end
end

local function log(m) if M.env.log then pcall(M.env.log, "[NCA] " .. tostring(m)) end end

function M.present() return S.attached end

-- One line for the Diagnostics hotkey. Answers, in order, the questions you actually have when the
-- row is missing: are they installed, did we attach, is our row in their list RIGHT NOW, and how many
-- times have they rebuilt the list under us.
function M.status()
  local mod, list, rowIn, n = nil, nil, false, 0
  pcall(function() mod = GetMod("NightCityAllies") end)
  pcall(function() list = S.app and S.app.availableInteractions end)
  -- ⚠️ CAPPED, for the same reason probe() is: this walks ANOTHER MOD'S table, and an unbounded
  -- ipairs over a table we did not build can run forever. loadsim's GetMod stub does exactly that,
  -- and status() is called every frame by the CET panel — so uncapped it hangs the offline suite AND
  -- would hang the game's draw loop against a proxy-backed table.
  if type(list) == "table" then
    pcall(function() n = math.min(#list, 60) end)
    for i = 1, n do
      local e = list[i]
      if type(e) == "table" and e.__jackielives then rowIn = true end
    end
  end
  return ("NCA: installed=%s attached=%s theirVer=%s rows=%d ourRowPresent=%s reasserts=%d tries=%d")
         :format(tostring(mod ~= nil), tostring(S.attached), tostring(S.modVer or "?"),
                 n, tostring(rowIn), S.reasserts or 0, S.tries)
end
function M.talking() return S.talking end

-- ---------------------------------------------------------------------------
-- PROBE — the whole state of the integration, in the log, in one keypress.
-- ---------------------------------------------------------------------------
-- Written because I diagnosed this wrong twice from symptoms alone. It answers, in order, every
-- question that "the Talk row isn't there" can actually mean:
--   1. is their mod loaded, and did we reach app?
--   2. is our row in their CURRENT list, at what index, out of how many?
--   3. what is in that list IN ORDER, with each row's condition evaluated — including entries their
--      menu never draws. That last part is why their "More ..." can appear with only six rows on
--      screen: their pagination counter counts filtered-out entries too.
--   4. for the npc their menu is on RIGHT NOW (app.ui.selectedNPC), does OUR condition say yes, and
--      which signal decided it — record, display name, or neither.
-- (4) is the one that matters when the row IS present and still invisible: it means their renderer
-- dropped it on the condition, not on the page.
function M.probe()
  local out = {}
  local function add(l) out[#out + 1] = l end
  add("----- NCA PROBE -----")

  local mod
  pcall(function() mod = GetMod("NightCityAllies") end)
  add(("installed=%s attached=%s theirVer=%s tries=%d reasserts=%d")
      :format(tostring(mod ~= nil), tostring(S.attached), tostring(S.modVer or "?"),
              S.tries, S.reasserts or 0))
  if not mod then add("Night City Allies is not loaded — nothing else to check."); add("----- END -----"); return out end

  local app
  pcall(function() app = mod.app end)
  add("mod.app reachable = " .. tostring(app ~= nil))
  if not app then add("their layout changed: no .app — the bridge cannot attach."); add("----- END -----"); return out end

  local list
  pcall(function() list = app.availableInteractions end)
  if type(list) ~= "table" then add("no app.availableInteractions table."); add("----- END -----"); return out end

  -- ⚠️ CAP THE READ. This walks ANOTHER MOD'S table, and a table we did not build can be anything —
  -- including a proxy with an __index that answers forever. loadsim's own GetMod stub is exactly that,
  -- and the first version of this probe hung the offline test suite outright. A real interaction list
  -- is ~10 rows; 60 is far past any sane menu and still terminates.
  local MAX = 60
  local n = 0
  pcall(function() n = math.min(#list, MAX) end)
  local ourIdx
  for i = 1, n do
    local e = list[i]
    if type(e) == "table" and e.__jackielives then ourIdx = i end
  end
  add(("their list: %d entries (showing %d) | our row at index %s")
      :format((function() local c = 0; pcall(function() c = #list end); return c end)(), n,
              ourIdx and tostring(ourIdx) or "NOT PRESENT"))

  local npc
  pcall(function() npc = app.ui and app.ui.selectedNPC end)
  local npcName = "(none - open their menu on a companion first, then press this)"
  pcall(function() if npc and npc.GetName then npcName = tostring(npc:GetName()) end end)
  add("their menu is currently on: " .. npcName)

  for i = 1, n do
    local e = list[i]
    if type(e) ~= "table" then break end
    local label, cond = "?", "n/a"
    pcall(function() label = tostring(e.label or "?") end)
    if e.condition and npc then
      local ok, r = pcall(e.condition, npc)
      cond = ok and tostring(r ~= false) or "ERROR"
    end
    add(("  %2d. %-22s cond=%-5s%s"):format(i, label, cond, e.__jackielives and "   <-- OURS" or ""))
  end

  if npc then
    local rec, byRec, byName = nil, false, false
    pcall(function()
      local id = npc:GetEntityID()
      local ent = id and Game.FindEntityByID(id)
      local r = ent and ent:GetRecordID()
      rec = r and tostring(r.value or r) or nil
      if rec and M.env.recordIsOurs then byRec = M.env.recordIsOurs(rec) and true or false end
    end)
    pcall(function()
      local nm, mine = npc:GetName(), M.env.personaName and M.env.personaName()
      if nm and mine then byName = tostring(nm):lower():find(tostring(mine):lower(), 1, true) ~= nil end
    end)
    add(("our condition: record=%s -> %s | name '%s' vs persona '%s' -> %s | VERDICT %s")
        :format(tostring(rec or "unresolved"), tostring(byRec), npcName,
                tostring((M.env.personaName and M.env.personaName()) or "?"), tostring(byName),
                tostring(byRec or byName)))
    add("(an unresolved record is normal - their npc id may not resolve to an entity; the name is the fallback)")
  end
  add("----- END NCA PROBE -----")
  return out
end

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
-- Honours the gating a pack author expects: `cond`, `minFam`, `chance`, `once`, `textPool` — and the
-- node-level `pick` sampler, including its sticky draw.
--
-- ⚠️ `pick` IS CONTENT, NOT A UI CONSTRAINT — I got this wrong first time and shipped it unhonoured.
-- It reads like a workaround for our box being a fixed-height list, and their renderer paginates, so
-- it looks safe to drop. It isn't: sampling is what stops a hub of thirty topics reading as a menu,
-- and what makes the same character feel different on a second visit. Dropping it doesn't reveal
-- more writing, it flattens the encounter. (Antonia, 2026-08-14: "it also makes interactions with
-- the character more interesting/surprising".)
--
-- Faithful to openChoiceMenu's sampler, because half of it would be worse than none:
--   • `pin = true` rows ALWAYS show and never count against the quota — the way out of a hub is
--     pinned, and a sample without it can strand the player in a menu with no exit.
--   • `last = true` IMPLIES `pin`, same as the engine.
--   • `pick` may be a RANGE `{lo, hi}`, re-rolled per open, so the menu's SHAPE varies too.
--   • THE DRAW STICKS for a cooldown. Without this, backing out of a topic and re-entering the hub
--     re-rolls, and a player can walk the whole pool in one conversation — which defeats both the
--     sampling and the familiarity pacing it exists to protect. The window runs from the last time
--     the hub was SEEN, so reopening holds the topics and walking away refreshes them.
local function rowsFor(node)
  local elig = {}
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
      if label and label ~= "" then
        elig[#elig + 1] = { choice = c, label = tostring(label), pin = (c.pin or c.last) and true or false }
      end
    end
  end
  if not (node and node.pick) or #elig == 0 then return elig end

  -- how many unpinned rows to offer this time
  local want
  if type(node.pick) == "table" then
    local lo = math.floor(tonumber(node.pick[1]) or 1)
    local hi = math.floor(tonumber(node.pick[2]) or lo)
    if hi < lo then lo, hi = hi, lo end
    want = lo
    pcall(function() want = math.random(lo, hi) end)
  else
    want = tonumber(node.pick) and math.floor(tonumber(node.pick)) or nil
  end
  want = want and math.max(1, want)

  local now = (M.env.now and M.env.now()) or 0
  S.draw = S.draw or {}
  local hd = S.draw[node]

  -- reuse a warm draw
  if want and hd and hd.set and now < (hd.until_ or 0) then
    local out, nonPinned = {}, 0
    for _, e in ipairs(elig) do
      if e.pin or hd.set[e.choice] then out[#out + 1] = e; if not e.pin then nonPinned = nonPinned + 1 end end
    end
    -- only honour it if there is still something to talk about (every cached topic may have been a
    -- `once` the player has since spent)
    if nonPinned > 0 then
      hd.until_ = now + (hd.hold or 20.0)
      return out
    end
  end

  if not want then return elig end
  local free = {}
  for i, e in ipairs(elig) do if not e.pin then free[#free + 1] = i end end
  if #free <= want then return elig end

  for i = #free, 2, -1 do                        -- Fisher-Yates over the index list
    local j = i; pcall(function() j = math.random(1, i) end)
    free[i], free[j] = free[j], free[i]
  end
  local keep = {}
  for i = 1, want do keep[free[i]] = true end
  local out, set = {}, {}
  for i, e in ipairs(elig) do
    if e.pin or keep[i] then out[#out + 1] = e; if not e.pin then set[e.choice] = true end end
  end
  local lo, hi = 10.0, 30.0
  if M.env.hubRefresh then pcall(function() lo, hi = M.env.hubRefresh() end) end
  local hold = lo
  pcall(function() hold = lo + math.random() * math.max(0, (hi or lo) - lo) end)
  S.draw[node] = { set = set, until_ = now + hold, hold = hold }
  return out
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
  -- ⚠️ FIRST, NOT LAST — and this is not a matter of taste.
  -- Their UI:choice paginates at MAX_CHOICES_PER_PAGE = 12: rows 1..13 render, then a "More ..."
  -- button, then the rest on page two. Appending put our row past that cut on a fully-kitted squad
  -- member, so in game it was invisible — behind a "More ..." that their own styling
  -- (gameinteractionsChoiceType.AlreadyRead) draws greyed out and that Antonia could not click
  -- (2026-08-15). Inserting at the front keeps Talk on page one whatever else they add, and it is
  -- also the right reading order: talk to her first, command her second.
  local ok = pcall(function() table.insert(list, 1, row) end)
  if not ok then log("could not insert our row"); return false end

  S.row, S.app, S.attached = row, app, true
  pcall(function() S.modVer = mod.version or mod.VERSION end)
  -- Their own event bus, when present: a session start is exactly when LoadModules() runs and our row
  -- disappears, so re-add immediately rather than waiting out the 5 s timer.
  pcall(function()
    if mod.On then mod:On("SessionStart", function() pcall(M.ensure) end) end
  end)
  log(("attached to Night City Allies%s — 'Talk' added to their menu for %s")
      :format(S.modVer and (" v" .. tostring(S.modVer)) or "",
              (M.env.personaName and M.env.personaName()) or "the active companion"))
  return true
end

-- ---------------------------------------------------------------------------
-- ⚠️ RE-ASSERT. THIS IS THE ONE THAT BIT.
-- ---------------------------------------------------------------------------
-- Their App:LoadModules() does
--     self.availableInteractions = self.moduleLoader:LoadInteractions()
-- i.e. it REPLACES the table rather than refilling it, and it runs at their init and again around a
-- session start. So a row we inserted goes in perfectly, reports as attached, and is then thrown away
-- wholesale with the table it was in — leaving us holding a reference to a list nothing renders.
-- Reported in game 2026-08-14: "the conversation hub was not added to the NCA list".
--
-- So attaching is not a one-off. ensure() re-checks the CURRENT table (never a cached row reference)
-- and puts our row back if it has gone. Cheap: an ipairs over ~8 rows on a 5 s timer.
function M.ensure()
  if not S.attached then return false end
  local list
  pcall(function() list = S.app and S.app.availableInteractions end)
  if type(list) ~= "table" then return false end
  for _, e in ipairs(list) do
    if type(e) == "table" and e.__jackielives then S.row = e; return true end
  end
  local row = M.buildRow()
  row.__jackielives = true
  local ok = pcall(function() table.insert(list, 1, row) end)   -- front: see the note in attach()
  if ok then
    S.row = row
    S.reasserts = (S.reasserts or 0) + 1
    log("their interaction list was rebuilt — re-added our Talk row (#" .. S.reasserts .. ")")
    return true
  end
  return false
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

M.reassertSeconds = 5.0

function M.tick(now)
  now = now or 0
  -- Already in: keep our row alive against their table being rebuilt (see M.ensure).
  if S.attached then
    if now < (S.nextEnsure or 0) then return end
    S.nextEnsure = now + M.reassertSeconds
    M.ensure()
    return
  end
  if S.tries >= M.maxTries then return end
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
