-- JackieLives — BRANCH AUDIT: the mechanical half of the two branch-logic rules
-- =============================================================================
--   cd JackieLives && lua tools/branch_audit.lua           # every pack
--                 lua tools/branch_audit.lua panam     # one pack
--
-- `docs/DIALOGUE.md` §9 says the two branch rules are not lintable. That is true of
-- the RULE — whether a reply answers what was said is a judgement — but three quarters
-- of the breaks have a mechanical signature, and this finds those. It reports
-- CANDIDATES for a human to judge, so it prints a count and always exits 0. It is
-- deliberately NOT wired into check_mod.lua: a heuristic that can fail a build is a
-- heuristic people delete.
--
-- What it looks for:
--
--   [CLOSER]  the character's line says she is FINISHED — "I'm done with this topic",
--             "talk to me later", "next question" — and the node then offers a menu.
--             This is rule 2 at its most visible: she says she is leaving and stays.
--             Highest-precision check here; treat a hit as a bug until proven otherwise.
--
--   [FILLER]  a leaf whose single choice is a short V row going back to the hub
--             ("Any time.", "...Right.", "Yeah."). The row exists because the engine
--             wanted a click. Candidate for a terminal node (no `choices` at all).
--             ⚠️ Not every hit is wrong: keep V's row where the character's line OPENS
--             something (a question, an invitation, "ask me something else").
--
--   [SPLIT]   a `companionPool` of N entries where a choice's distinctive words appear
--             in exactly ONE entry. That is the signature of rule 1 — the row was
--             written while looking at one entry and is a non-sequitur after the others.
--
--   [JUMP]    a choice pointing at a node owned by a DIFFERENT topic. The destination's
--             pool was written to answer that topic's question, not this one. Re-read
--             the destination before trusting the row.
--
--   [ORPHAN]  a choice with no word in common with any pool entry AND no word in common
--             with the node's own question. Weakest signal, most noise — it is last for
--             that reason, and it is off unless you pass `--orphans`.
-- =============================================================================

local here = arg and arg[0] and arg[0]:match("^(.*)/[^/]*$") or "."
package.path = here .. "/../mod/JackieLives/?.lua;" .. package.path
local MOD = "JackieLives"

-- ⚠️ JackieLives has NO voices.lua — persona #0's whole conversation lives in config.lua
-- (`Config.dialogueTree`, `Config.callTree`, `Config.date.*`). So this port always reads
-- config; the `--config` switch that NCLives needs is implied here and kept only so the
-- two copies of this file stay diff-able.

local only, wantOrphans, fromConfig, wantCtx = nil, false, true, false
for _, a in ipairs(arg or {}) do
  if a == "--orphans" then wantOrphans = true
  elseif a == "--context" then wantCtx = true
  elseif a == "--config" then fromConfig = true
  elseif not a:match("^%-%-") then only = a end
end

-- ---------------------------------------------------------------------------
local STOP = {}
for w in ([[
about after again against all also and any are because been before being both but
came can cant come could did didnt does doesnt doing dont down each even ever every
first for from get gets getting give going gone got had has have having her here
hers him his how into its itself just keep kept know known let like little long
made make many may more most much must never new not now off once one only onto
other our out over own put said same say says see seen she should since some still
such take than that thats the their them then there these they thing things think
this those through time too took under until very want was way well went were what
when where which while who why will with without would you your yours
]]):gmatch("%a+") do STOP[w] = true end

local function words(s)
  local out = {}
  for raw in tostring(s or ""):lower():gsub("[^%a%s']", " "):gmatch("[%a']+") do
    local w = raw:gsub("'", "")
    if #w >= 4 and not STOP[w] then out[w] = true end
  end
  return out
end

local function anyShared(a, b) for w in pairs(a) do if b[w] then return true end end return false end

-- The character's line(s) on a node, as a list of strings.
-- ⚠️ FIELD NAMES. NCLives renamed `jackie`/`jackiePool` to `companion`/`companionPool`
-- in its v1.2; JackieLives never did, because here the character IS Jackie. Read both, so
-- this file is the same file in all three repos.
local function linesOf(node)
  local out = {}
  local one  = node.companion or node.jackie
  local pool = node.companionPool or node.jackiePool
  if type(one) == "table" and one.text then out[#out + 1] = one.text end
  for _, e in ipairs(pool or {}) do
    if type(e) == "table" and e.text then out[#out + 1] = e.text elseif type(e) == "string" then out[#out + 1] = e end
  end
  return out
end

-- The text a choice row shows. `variants` / `textPool` rows show one of several.
local function choiceTexts(ch)
  local out = {}
  if type(ch.text) == "string" then out[#out + 1] = ch.text end
  for _, v in ipairs(ch.variants or ch.textPool or {}) do
    if type(v) == "table" and v.text then out[#out + 1] = v.text elseif type(v) == "string" then out[#out + 1] = v end
  end
  return out
end

-- ⚠️ A CLOSER IS A PROMISE. If the line says she is finished, the node has to be
-- finished — a menu after it is the character contradicting herself on screen.
-- Phrases only, never single words: "leave it" inside "don't leave it too long" is
-- not a closer, and a word list would call it one.
-- ⚠️ HARD closers only — she is finished RIGHT NOW. A DEFERRAL is not a closer:
-- "ask me again in a year", "ask me again next week", "don't ask me why" are all
-- legitimate leaves that V can answer, and putting them in this list is what makes
-- the check noisy enough to ignore. The test is: could the box close on this line
-- without the player feeling cut off?
local CLOSERS = {
  "done with this", "done with that", "done talkin", "done with the subject",
  "enough of that", "leave it there", "we can leave that", "leave that where it fell",
  "going to stop talking", "stop talking now", "talk to me later", "talk later",
  "i'm going to go check", "im going to go check",
  "don't ask me again for a while", "dont ask me again for a while",
  "that's all you get", "thats all you get", "i'll leave it at that", "ill leave it at that",
  "you can work out the rest", "end of that story", "that's the end of that",
  "not saying any more", "we're done", "were done", "i'm done here", "im done here",
}
local function closerIn(s)
  s = tostring(s or ""):lower()
  for _, p in ipairs(CLOSERS) do if s:find(p, 1, true) then return p end end
end

-- ---------------------------------------------------------------------------
-- Topic ownership: BFS out of each hub row, never walking back through a hub. A node
-- reached from two topics is SHARED and never reported as a cross-topic jump.
local function ownership(tree)
  local hubs, own = {}, {}
  for k, n in pairs(tree.nodes) do if type(n) == "table" and n.silent then hubs[k] = true end end
  if not next(hubs) then hubs[tree.start] = true end
  local roots = {}
  for h in pairs(hubs) do
    for _, ch in ipairs(tree.nodes[h].choices or {}) do
      if type(ch.to) == "string" and not hubs[ch.to] then roots[ch.to] = true end
    end
  end
  for r in pairs(roots) do
    local stack, seen = { r }, { [r] = true }
    while #stack > 0 do
      local k = table.remove(stack)
      own[k] = own[k] or {}
      own[k][r] = true
      for _, ch in ipairs((tree.nodes[k] or {}).choices or {}) do
        local t = ch.to
        if type(t) == "string" and not hubs[t] and not seen[t] and tree.nodes[t] then
          seen[t] = true; stack[#stack + 1] = t
        end
      end
    end
  end
  return hubs, own
end

-- ---------------------------------------------------------------------------
local hits = 0
local function report(where, kind, msg, detail)
  hits = hits + 1
  print(string.format("  [%s] %s", kind, where))
  print("        " .. msg)
  if detail then print("        " .. detail) end
end

local function auditTree(label, tree)
  if type(tree) ~= "table" or type(tree.nodes) ~= "table" then return end
  local hubs, own = ownership(tree)
  local keys = {}
  for k in pairs(tree.nodes) do keys[#keys + 1] = k end
  table.sort(keys)

  for _, k in ipairs(keys) do
    local node = tree.nodes[k]
    if type(node) == "table" then
      local at = label .. "." .. k
      local lines = linesOf(node)
      local choices = node.choices or {}

      -- [CLOSER]
      if #choices > 0 then
        for _, ln in ipairs(lines) do
          local p = closerIn(ln)
          if p then
            report(at, "CLOSER",
                   'she says "' .. p .. '" and the node still offers ' .. #choices .. " row(s)",
                   '"' .. ln .. '"')
            break
          end
        end
      end

      -- [FILLER]
      if #choices == 1 then
        local ch = choices[1]
        local txts = choiceTexts(ch)
        local t = txts[1]
        if t and type(ch.to) == "string" and hubs[ch.to] and not ch.action then
          local n = 0; for _ in t:gmatch("%S+") do n = n + 1 end
          if n <= 4 then
            report(at, "FILLER", 'V\'s only row is "' .. t .. '" -> ' .. ch.to,
                   #lines == 1 and ('"' .. lines[1] .. '"') or nil)
          end
        end
      end

      -- [SPLIT] / [JUMP] / [ORPHAN]
      if #lines >= 2 then
        local lw = {}
        for i, ln in ipairs(lines) do lw[i] = words(ln) end
        for _, ch in ipairs(choices) do
          for _, t in ipairs(choiceTexts(ch)) do
            local cw = words(t)
            local matched = {}
            for i, w in ipairs(lw) do if anyShared(cw, w) then matched[#matched + 1] = i end end
            if #matched == 1 then
              report(at, "SPLIT",
                     'row "' .. t .. '" only shares wording with answer #' .. matched[1] .. ' of ' .. #lines,
                     '#' .. matched[1] .. ': "' .. lines[matched[1]] .. '"')
            elseif wantOrphans and #matched == 0 and next(cw) then
              report(at, "ORPHAN", 'row "' .. t .. '" shares no wording with any of the ' .. #lines .. " answers")
            end
          end
        end
      end

      for _, ch in ipairs(choices) do
        local t = ch.to
        if type(t) == "string" and not hubs[t] and own[k] and own[t] then
          local shared = false
          for r in pairs(own[k]) do if own[t][r] then shared = true break end end
          if not shared then
            local mine, theirs = {}, {}
            for r in pairs(own[k]) do mine[#mine + 1] = r end
            for r in pairs(own[t]) do theirs[#theirs + 1] = r end
            table.sort(mine); table.sort(theirs)
            report(at, "JUMP",
                   'row "' .. (choiceTexts(ch)[1] or "?") .. '" jumps into the `'
                   .. table.concat(theirs, "/") .. '` topic (this node belongs to `'
                   .. table.concat(mine, "/") .. '`)',
                   'that node answers a different question — re-read its pool')
          end
        end
      end
    end
  end
end

-- ---------------------------------------------------------------------------
print("BRANCH AUDIT — " .. MOD .. (only and (" (" .. only .. ")") or ""))
print("candidates for a human to judge; nothing here is automatically a bug\n")

if fromConfig then
  local Config = require("config")
  print("== config.lua (persona #0) ==")
  auditTree("dialogueTree", Config.dialogueTree)
  auditTree("everywhere", Config.locationDialogue and Config.locationDialogue.everywhere)
  auditTree("callTree", Config.callTree)
  auditTree("dinnerTree", Config.date and Config.date.tree)
  auditTree("seatedTree", Config.date and Config.date.seatedTree)
else
  local names = {}
  for k in pairs(require("voices").packs) do names[#names + 1] = k end
  table.sort(names)
  for _, key in ipairs(names) do
    if not only or only == key then
      local pack = Voices.packs[key]
      local before = hits
      print("== " .. key .. " ==")
      auditTree("talkTree", pack.talkTree)
      auditTree("seatedTree", pack.seatedTree)
      auditTree("callTree", pack.callTree)
      auditTree("dinnerTree", pack.dinnerTree)
      if hits == before then print("  (nothing flagged)") end
      print("")
    end
  end
end

print(string.format("%d candidate(s). Read docs/DIALOGUE.md §9 before changing any of them.", hits))
