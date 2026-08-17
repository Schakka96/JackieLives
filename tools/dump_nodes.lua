-- JackieLives — print a dialogue node exactly as the player meets it: the line(s) the
-- character can open with, then every row V can pick and where it goes.
--
--   lua tools/dump_nodes.lua --config dialogueTree.howbeen
--   lua tools/dump_nodes.lua --config --all-of dialogueTree
--
-- The companion piece to `branch_audit.lua`: the audit tells you WHICH node to look
-- at, this shows you the thing you actually have to judge. Reading it in voices.lua
-- means scrolling past the pack header and the gating fields; this is just the beat.
local here = arg and arg[0] and arg[0]:match("^(.*)/[^/]*$") or "."
package.path = here .. "/../mod/JackieLives/?.lua;" .. package.path

local a, fromConfig, allOf = {}, false, nil
local i = 1
while arg[i] do
  if arg[i] == "--config" then fromConfig = true
  elseif arg[i] == "--all-of" then i = i + 1; allOf = arg[i]
  else a[#a + 1] = arg[i] end
  i = i + 1
end

local trees = {}
if fromConfig then
  local Config = require("config")
  -- ⚠️ `everywhere` is the tree a FOLLOWING companion actually gets (currentTalkTree()
  -- prefers it), so it is the one to read when a beat looks wrong in game. `dialogueTree`
  -- is only the safety net behind it.
  trees.dialogueTree = Config.dialogueTree
  trees.everywhere   = Config.locationDialogue and Config.locationDialogue.everywhere
  trees.callTree     = Config.callTree
  trees.dinnerTree   = Config.date and Config.date.tree
  trees.seatedTree   = Config.date and Config.date.seatedTree
  for k, v in pairs(Config.locationDialogue or {}) do trees[k] = v end
else
  local pack = require("voices").packs[a[1]] or error("no pack '" .. tostring(a[1]) .. "'")
  table.remove(a, 1)
  trees.talkTree, trees.seatedTree = pack.talkTree, pack.seatedTree
  trees.callTree, trees.dinnerTree = pack.callTree, pack.dinnerTree
end

local function gates(c)
  local g = {}
  if c.minFam then g[#g + 1] = "fam>=" .. c.minFam end
  if c.fam    then g[#g + 1] = "fam" .. (c.fam > 0 and "+" or "") .. c.fam end
  if c.chance then g[#g + 1] = "chance " .. c.chance end
  if c.once   then g[#g + 1] = "once" end
  if c.cond   then g[#g + 1] = "cond" end
  if c.action then g[#g + 1] = "!" .. c.action end
  return #g > 0 and ("  [" .. table.concat(g, ", ") .. "]") or ""
end

local function show(tname, key)
  local tree = trees[tname]
  local node = tree and tree.nodes and tree.nodes[key]
  if not node then print("?? " .. tname .. "." .. key .. " not found"); return end
  print("\n-- " .. tname .. "." .. key .. (node.silent and "   (silent hub)" or ""))
  -- ⚠️ VOICED marks a line whose subtitle IS a CDPR recording. Its words are not ours to
  -- reword — see docs/DIALOGUE.md "the subtitle is the line". Fix such a beat on V's row.
  -- ⚠️ `jackie`/`jackiePool` are the same fields under NCLives' pre-v1.2 names — see
  -- branch_audit.lua. Persona #0 still uses them.
  local one  = node.companion or node.jackie
  local pool = node.companionPool or node.jackiePool
  if one and one.text then
    print("   L:" .. (one.sfx and " VOICED" or "") .. " " .. one.text)
  end
  for n, e in ipairs(pool or {}) do
    local t = type(e) == "table" and e.text or e
    print(string.format("   L%d:%s%s %s", n,
      (type(e) == "table" and e.sfx) and " VOICED" or "",
      (type(e) == "table" and e.minFam) and (" [fam>=" .. e.minFam .. "]") or "", t))
  end
  for _, c in ipairs(node.choices or {}) do
    local t = c.text
    if not t then
      local vs = {}
      for _, v in ipairs(c.variants or c.textPool or {}) do vs[#vs + 1] = (type(v) == "table" and v.text or v) end
      t = "{" .. table.concat(vs, " | ") .. "}"
    end
    print(string.format("   V: %-52s -> %s%s", t, tostring(c.to), gates(c)))
  end
  if not node.choices or #node.choices == 0 then print("   (TERMINAL — the box closes on her line)") end
end

if allOf then
  local keys = {}
  for k in pairs(trees[allOf].nodes) do keys[#keys + 1] = k end
  table.sort(keys)
  for _, k in ipairs(keys) do show(allOf, k) end
else
  for _, spec in ipairs(a) do
    local t, k = spec:match("^([%w_]+)%.(.+)$")
    if t then show(t, k) else print("?? bad spec '" .. spec .. "' (want tree.node)") end
  end
end
