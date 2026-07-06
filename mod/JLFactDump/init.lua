-- JLFactDump v2 — quest-state capture tool for the "Save Jackie" main-quest datamining SPIKE.
--
-- Standalone CET mod (independent of JackieLives — it does not touch the working mod).
--
-- WHY v2: v1 only hooked QuestsSystem:SetFact, which captures the game's shallow WORLD-REACTION
-- facts (wanted_level, ripperdocs_visited, delamain phonecalls). The main quest — the Heist tail,
-- the Watson lockdown lift, Jackie's death, Johnny/Relic — advances through the QUEST GRAPH and the
-- JOURNAL, which do NOT pass through SetFact. So v1's log was structurally blind to the levers we
-- need. v2 adds two channels that DO see that layer:
--
--   (A) JOURNAL hook  — Observe gameJournalManager:ChangeEntryState. Every quest/objective/phase
--       flip (Heist -> Succeeded, the internal Lockdown quest completing, Playing for Time going
--       Active) fires through here. This is the real main-quest state machine.  src = "journal"
--
--   (B) READ-POLL     — we can't hook graph-set facts being WRITTEN, but we can READ them. Every
--       ~0.75s we read a curated SUSPECT LIST with GetFactStr and log any value that CHANGED.
--       This surfaces facts the graph sets internally that a SetFact hook never sees.  src = "poll"
--       (We deliberately do NOT hook GetFact globally — the game reads facts thousands of times a
--        second and it would flood the log. Polling a known suspect list is the controlled version.)
--
--   (C) WRITE hook    — the original SetFact / SetFactStr capture, kept for completeness.
--                                                                          src = "cname" / "str"
--
-- All four channels write the SAME line format factdiff.py already parses:
--     NNNNNN <TAB> SET <TAB> <src> <TAB> <name>=<value>
--     === MARKER <TAB> NNNNNN <TAB> <label> ===
--
-- HOW TO USE: see SPIKE.md. Short version: install, open overlay (~), click Self-test, do a small
-- action and confirm NEW lines appear (journal lines when an objective ticks, poll lines when a
-- fact changes), then load a pre-Heist-ending save and press a marker hotkey at each story moment.

local FD = {
  open = true,
  overlayOpen = false,
  seq = 0,
  hooks = {},
  sets = 0,        -- SetFact writes captured
  journal = 0,     -- journal state-changes captured
  polls = 0,       -- poll changes logged
  markers = 0,
  pollAccum = 0.0,
}

local LOGFILE = "factdump.log"
local POLL_INTERVAL = 0.75   -- seconds between suspect-list reads

-- ---------------------------------------------------------------------------
-- SUSPECT LIST for the read-poll (channel B).
-- These are candidate fact names we watch for a value change. Reading a name that doesn't exist
-- just returns 0 (harmless), so it is SAFE to over-seed — false candidates cost nothing. ADD any
-- names you spot in Fact Finder here and re-run; the more suspects, the better the coverage.
-- Seeded from docs/research (q005 body facts + Act-1->Act-2 transition guesses).
-- ---------------------------------------------------------------------------
local SUSPECTS = {
  -- CONFIRMED REAL on Antonia's build (2026-07-06 run): these two are our core pair.
  "q005_done",       -- [WATSON] Heist complete — flips 1 at the Heist end
  "q101_started",    -- [AVOID]  Act-2/Johnny opener — must NOT be 1 in our route
  -- Siblings of the confirmed convention (qNNN_started / qNNN_done) — capture ordering + earlier gates
  "q005_started", "q101_done",
  "q003_started", "q003_done",   -- The Pickup
  "q004_started", "q004_done",   -- The Information
  "q101_01_started", "q101_01_done", "q101_02_started", "q101_02_done",
  -- Jackie's body destination at the end of the Heist (gates the ofrenda/mourning)
  "q005_jackie_to_hospital",
  "q005_jackie_to_mama",
  "q005_jackie_stay_notell",
  -- Other Heist / prologue completion + lockdown lever guesses (names are guesses — safe, read=0 if absent)
  "q005_heist", "q005_complete", "q005_finished", "q005_end",
  "prologue_done", "prologue_complete", "prologue_finished",
  "watson_lockdown", "watson_lockdown_lifted", "lockdown", "lockdown_lifted",
  "lockdown_over", "lockdown_done", "lockdown_started",
  "district_watson_locked", "prevention_watson",
  "act_01_done", "act_02", "act_02_start", "act2_start", "act_02_started",
  "open_world", "world_open", "fast_travel_unlocked",
  -- Act-2 opener / Relic / Johnny — the rest of the AVOID set
  "q101_resurrection", "q101", "q101_start",
  "q101_01_firestorm", "love_like_fire", "johnny_active", "johnny_intro",
  "relic_active", "biochip_installed", "chip_installed", "engram_active",
  -- Number-of-things counters we already saw move (baseline sanity)
  "number_of_ripperdocs_visited",
}

-- Your four story moments (plus two spares). Order does NOT matter — each press timestamps a line.
local MARKERS = {
  { key = "jlfd_m1", label = "1_heist_complete",            desc = "1) The Heist complete" },
  { key = "jlfd_m2", label = "2_v_gets_shot",               desc = "2) V gets shot (No-Tell Motel)" },
  { key = "jlfd_m3", label = "3_love_like_fire_johnny_mem", desc = "3) Love Like Fire / Johnny memories" },
  { key = "jlfd_m4", label = "4_playing_for_time",          desc = "4) Playing for Time starts" },
  { key = "jlfd_mA", label = "A_custom",                    desc = "A) Spare marker" },
  { key = "jlfd_mB", label = "B_custom",                    desc = "B) Spare marker" },
}

-- gameJournalEntryState is an enum; Observe hands it over as an int on most builds. Best-effort map
-- (raw value is always kept too, so a wrong label never loses information).
local JOURNAL_STATE = { [0] = "Inactive", [1] = "Active", [2] = "Succeeded", [3] = "Failed" }

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
-- passes a CName — try the known resolvers, fall back to tostring (a hash is still diffable).
local function nameToStr(n)
  if type(n) == "string" then return n end
  local s
  if pcall(function() s = Game.NameToString(n) end) and s and s ~= "" and s ~= "None" then return s end
  if pcall(function() s = NameToString(n) end)      and s and s ~= "" and s ~= "None" then return s end
  if pcall(function() s = n.value end)              and s and s ~= "" then return tostring(s) end
  return tostring(n)
end

local function journalStateStr(state)
  local n = tonumber(state)
  if n and JOURNAL_STATE[n] then return JOURNAL_STATE[n] .. "/" .. tostring(n) end
  return tostring(state)
end

-- ---- channel C: SetFact writes ----
local function logSet(src, name, value)
  FD.sets = FD.sets + 1
  writeLine(seqStr() .. "\tSET\t" .. src .. "\t" .. nameToStr(name) .. "=" .. tostring(value))
end

-- ---- channel A: journal state changes ----
local function logJournal(className, hash, state)
  FD.journal = FD.journal + 1
  -- name embeds the class so factdiff's name patterns (e.g. "Quest") can flag it; value = state.
  local nm = tostring(className) .. "#" .. tostring(hash)
  writeLine(seqStr() .. "\tSET\tjournal\t" .. nm .. "=" .. journalStateStr(state))
end

-- ---- channel B: poll changes ----
local function logPoll(name, value)
  FD.polls = FD.polls + 1
  writeLine(seqStr() .. "\tSET\tpoll\t" .. name .. "=" .. tostring(value))
end

local function dropMarker(label)
  FD.markers = FD.markers + 1
  writeLine("=== MARKER\t" .. seqStr() .. "\t" .. tostring(label) .. " ===")
  print("[JLFactDump] MARKER: " .. tostring(label))
end

-- Register an Observe hook defensively. If the class/method name is wrong for this build, pcall
-- swallows it and the mod keeps working; the ones that DO exist attach.
local function tryHook(class, method, fn)
  local ok = pcall(function() Observe(class, method, fn) end)
  if ok then FD.hooks[#FD.hooks + 1] = class .. ":" .. method end
end

-- Read one suspect; return the value as string (GetFactStr returns 0 for unset — that's fine).
local function readFact(name)
  local v
  local ok = pcall(function() v = Game.GetQuestsSystem():GetFactStr(name) end)
  if ok and v ~= nil then return tostring(v) end
  return nil
end

local pollPrev = {}   -- name -> last seen value string

local function pollOnce(baseline)
  for _, name in ipairs(SUSPECTS) do
    local v = readFact(name)
    if v ~= nil then
      local prev = pollPrev[name]
      if prev == nil then
        -- first read: record baseline. Only LOG non-zero baselines (zeros are just "unset" noise),
        -- unless this is the explicit startup baseline pass.
        pollPrev[name] = v
        if baseline and v ~= "0" then logPoll(name, v) end
      elseif prev ~= v then
        pollPrev[name] = v
        logPoll(name, v)
      end
    end
  end
end

registerForEvent("onInit", function()
  -- fresh log each game load (seq resets too)
  pcall(function() local f = io.open(LOGFILE, "w"); if f then f:close() end end)
  writeLine("=== JLFactDump v2 session start (seq resets each game load) ===")

  -- (C) SetFact writes — short RTTI class form first, then a fallback spelling.
  tryHook("QuestsSystem",      "SetFact",    function(self, a, b) logSet("cname", a, b) end)
  tryHook("QuestsSystem",      "SetFactStr", function(self, a, b) logSet("str",   a, b) end)
  tryHook("gameIQuestsSystem", "SetFact",    function(self, a, b) logSet("cname2", a, b) end)
  tryHook("gameIQuestsSystem", "SetFactStr", function(self, a, b) logSet("str2",  a, b) end)

  -- (A) JOURNAL state changes. Signature: ChangeEntryState(hash, className, state, notifyOption).
  -- Try the short and long class spellings; duplicates are harmless (factdiff collapses per seg).
  tryHook("gameJournalManager", "ChangeEntryState",
    function(self, hash, className, state) logJournal(className, hash, state) end)
  tryHook("JournalManager", "ChangeEntryState",
    function(self, hash, className, state) logJournal(className, hash, state) end)

  local anyWrite = false
  for _, h in ipairs(FD.hooks) do if h:find("SetFact") then anyWrite = true end end
  if #FD.hooks == 0 then
    print("[JLFactDump] WARNING: no hooks registered — use the Fact Finder fallback (see SPIKE.md).")
    writeLine("=== WARNING: no hooks registered ===")
  else
    local msg = "hooked: " .. table.concat(FD.hooks, ", ")
    print("[JLFactDump] " .. msg)
    writeLine("=== " .. msg .. " ===")
  end
  if not anyWrite then
    writeLine("=== NOTE: SetFact write-hook did not attach; relying on journal + poll channels ===")
  end

  -- (B) startup baseline poll: record where the suspects stand right now (logs non-zero ones).
  writeLine("=== poll baseline (suspects with non-zero starting value) ===")
  pollOnce(true)

  print("[JLFactDump] v2 ready (write + journal + poll). Validate on a REAL change before the Heist run.")
end)

registerForEvent("onOverlayOpen",  function() FD.overlayOpen = true end)
registerForEvent("onOverlayClose", function() FD.overlayOpen = false end)

-- Channel B ticks here — accumulate dt and poll the suspect list every POLL_INTERVAL seconds.
registerForEvent("onUpdate", function(dt)
  FD.pollAccum = FD.pollAccum + (dt or 0)
  if FD.pollAccum >= POLL_INTERVAL then
    FD.pollAccum = 0.0
    pcall(pollOnce, false)
  end
end)

registerForEvent("onDraw", function()
  if not FD.open then return end
  if ImGui.Begin("JL Fact Dump v2") then
    ImGui.Text("Hooks: " .. (#FD.hooks > 0 and table.concat(FD.hooks, ", ") or "NONE — see SPIKE.md"))
    ImGui.Text(string.format("Writes: %d   Journal: %d   Poll changes: %d   Markers: %d",
      FD.sets, FD.journal, FD.polls, FD.markers))
    ImGui.Text(string.format("Suspect list: %d facts, polled every %.2fs", #SUSPECTS, POLL_INTERVAL))
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
    ImGui.Text("Validate on a REAL change before the costly Heist run:")
    ImGui.Text("  - loot/finish an objective -> expect a 'journal' line")
    ImGui.Text("  - or a poll line when a watched fact flips")
  end
  ImGui.End()
end)

-- Hotkeys so you can mark moments DURING gameplay/cutscenes without opening the overlay.
-- Bind them in  CET overlay > Bindings (Hotkeys)  after the mod loads.
for _, m in ipairs(MARKERS) do
  registerHotkey(m.key, "Marker: " .. m.desc, function() dropMarker(m.label) end)
end
registerHotkey("jlfd_toggle", "Show/Hide Fact Dump window", function() FD.open = not FD.open end)
