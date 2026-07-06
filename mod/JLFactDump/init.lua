-- JLFactDump — quest-fact capture tool for the "Save Jackie" main-quest datamining SPIKE.
--
-- Standalone CET mod (independent of JackieLives — it does not touch the working mod).
-- It records every quest FACT the game sets, plus manual MARKER lines you drop at key story
-- moments, into  factdump.log  in this mod's own folder. You then diff the segments offline on
-- the Mac with  tools/factdiff/factdiff.py .
--
-- WHY: we need to find, on your real game, (a) the fact(s) that lift the Watson lockdown when the
-- Heist ends, and (b) the q101 / Johnny facts we must NEVER trigger. Those names are undocumented,
-- so we capture them live. Play the VANILLA Heist ending once on a THROWAWAY save while this logs.
--
-- HOW TO USE (full steps in SPIKE.md):
--   1. Copy this JLFactDump folder into
--        Cyberpunk 2077\bin\x64\plugins\cyber_engine_tweaks\mods\
--   2. Launch the game, open the CET overlay (~), you should see the "JL Fact Dump" window.
--   3. VALIDATE FIRST (cheap): click "Self-test" — a  jlfd_selftest=…  line must appear in
--      factdump.log. Then do any small in-game action that changes a fact (loot something / finish
--      a tiny objective) and confirm NEW  SET  lines appear. If nothing is captured on a real
--      change, this build can't hook the native setter → use the Fact Finder fallback (see SPIKE.md).
--   4. Load a save shortly BEFORE the Heist ends. Play the vanilla ending. Press the matching
--      marker hotkey (or overlay button) at each of your 4 moments.
--   5. Copy factdump.log to the Mac and run factdiff.py.

local FD = {
  open = true,
  overlayOpen = false,
  seq = 0,
  hooks = {},
  sets = 0,
  markers = 0,
}

local LOGFILE = "factdump.log"

-- Your four story moments (plus two spares). Order does NOT matter to the tool — each press just
-- timestamps a line. Likely chronology is 1 -> 2 -> 4 -> 3 (Love Like Fire comes AFTER Playing for
-- Time begins). Rename the labels freely; keep the keys unique.
local MARKERS = {
  { key = "jlfd_m1", label = "1_heist_complete",            desc = "1) The Heist complete" },
  { key = "jlfd_m2", label = "2_v_gets_shot",               desc = "2) V gets shot (No-Tell Motel)" },
  { key = "jlfd_m3", label = "3_love_like_fire_johnny_mem", desc = "3) Love Like Fire / Johnny memories" },
  { key = "jlfd_m4", label = "4_playing_for_time",          desc = "4) Playing for Time starts" },
  { key = "jlfd_mA", label = "A_custom",                    desc = "A) Spare marker" },
  { key = "jlfd_mB", label = "B_custom",                    desc = "B) Spare marker" },
}

local function seqStr()
  FD.seq = FD.seq + 1
  return string.format("%06d", FD.seq)
end

local function writeLine(line)
  pcall(function()
    local f = io.open(LOGFILE, "a")
    if f then f:write(line .. "\n"); f:close() end
  end)
end

-- Resolve a fact-name arg to a readable string. SetFactStr passes a Lua string already; SetFact
-- passes a CName — try the known resolvers, fall back to tostring (a hash is still diffable, and
-- factdiff can map it later against a name list if needed).
local function nameToStr(n)
  if type(n) == "string" then return n end
  local s
  if pcall(function() s = Game.NameToString(n) end) and s and s ~= "" and s ~= "None" then return s end
  if pcall(function() s = NameToString(n) end)      and s and s ~= "" and s ~= "None" then return s end
  if pcall(function() s = n.value end)              and s and s ~= "" then return tostring(s) end
  return tostring(n)
end

local function logSet(src, name, value)
  FD.sets = FD.sets + 1
  writeLine(seqStr() .. "\tSET\t" .. src .. "\t" .. nameToStr(name) .. "=" .. tostring(value))
end

local function dropMarker(label)
  FD.markers = FD.markers + 1
  writeLine("=== MARKER\t" .. seqStr() .. "\t" .. tostring(label) .. " ===")
  print("[JLFactDump] MARKER: " .. tostring(label))
end

-- Register an Observe hook defensively. If the class/method name is wrong for this build, pcall
-- swallows it and the mod keeps working; the ones that DO exist attach. Duplicate captures across
-- class spellings are harmless — factdiff collapses them to one value per fact per segment.
local function tryHook(class, method, src)
  local ok = pcall(function()
    Observe(class, method, function(self, a, b)
      logSet(src, a, b)   -- a = fact name, b = value  (SetFact / SetFactStr both are (name, value))
    end)
  end)
  if ok then FD.hooks[#FD.hooks + 1] = class .. ":" .. method end
end

registerForEvent("onInit", function()
  -- fresh log each game load (seq resets too)
  pcall(function() local f = io.open(LOGFILE, "w"); if f then f:close() end end)
  writeLine("=== JLFactDump session start (seq resets each game load) ===")

  -- Short RTTI class form first (this project hooks "PhoneSystem"/"PlayerPuppet" the same way),
  -- then a fallback spelling in case this build differs.
  tryHook("QuestsSystem",     "SetFact",    "cname")
  tryHook("QuestsSystem",     "SetFactStr", "str")
  tryHook("gameIQuestsSystem", "SetFact",    "cname2")
  tryHook("gameIQuestsSystem", "SetFactStr", "str2")

  if #FD.hooks == 0 then
    print("[JLFactDump] WARNING: no fact hook registered — use the Fact Finder fallback (see SPIKE.md).")
    writeLine("=== WARNING: no fact hook registered ===")
  else
    local msg = "hooked: " .. table.concat(FD.hooks, ", ")
    print("[JLFactDump] " .. msg)
    writeLine("=== " .. msg .. " ===")
  end
  print("[JLFactDump] ready. IMPORTANT: validate capture on a REAL fact change before the Heist run.")
end)

registerForEvent("onOverlayOpen",  function() FD.overlayOpen = true end)
registerForEvent("onOverlayClose", function() FD.overlayOpen = false end)

registerForEvent("onDraw", function()
  if not FD.open then return end
  if ImGui.Begin("JL Fact Dump") then
    ImGui.Text("Hooks: " .. (#FD.hooks > 0 and table.concat(FD.hooks, ", ") or "NONE — see SPIKE.md"))
    ImGui.Text(string.format("Facts captured: %d     Markers: %d", FD.sets, FD.markers))
    ImGui.Separator()
    ImGui.Text("Drop a marker at each story moment")
    ImGui.Text("(or use the hotkeys — they work without the overlay open):")
    for _, m in ipairs(MARKERS) do
      if ImGui.Button(m.desc) then dropMarker(m.label) end
    end
    ImGui.Separator()
    if ImGui.Button("Self-test (writes a known fact)") then
      pcall(function()
        Game.GetQuestsSystem():SetFactStr("jlfd_selftest", (os and os.time and os.time()) or FD.seq)
      end)
      print("[JLFactDump] self-test fact set; look for a jlfd_selftest line in factdump.log")
    end
    ImGui.Text("Log: mods/JLFactDump/factdump.log")
    ImGui.Text("Validate on a REAL fact change before the costly Heist run.")
  end
  ImGui.End()
end)

-- Hotkeys so you can mark moments DURING gameplay/cutscenes without opening the overlay.
-- Bind them in  CET overlay > Bindings (Hotkeys)  after the mod loads.
for _, m in ipairs(MARKERS) do
  registerHotkey(m.key, "Marker: " .. m.desc, function() dropMarker(m.label) end)
end
registerHotkey("jlfd_toggle", "Show/Hide Fact Dump window", function() FD.open = not FD.open end)
