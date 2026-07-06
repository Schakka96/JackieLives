# SPIKE — find the Watson-unlock fact (and confirm the Johnny split)

**Goal of this experiment:** on YOUR real game, capture exactly which quest facts flip when the
Heist ends, so we can find the lever that opens the world (Watson lockdown) **and** confirm the
Johnny/Relic facts we must never trigger. These names are undocumented, so we record them live.

This is **observation only** — you play the *vanilla* Heist ending on a throwaway save and just
watch the facts. We change nothing yet. Do it on a **backup/disposable save** anyway.

---

## Part 0 — What you need
- Cyber Engine Tweaks already installed (you have it).
- A save **shortly before the Heist ends** — ideally right before the Konpeki escape / the Delamain
  cab. If you don't have one, keep a manual save from your current playthrough, or grab a
  "before The Heist" save; we only need to watch the ending once.

## Part 1 — Install the logger
1. Copy the whole **`JLFactDump`** folder into:
   `Cyberpunk 2077\bin\x64\plugins\cyber_engine_tweaks\mods\`
   (so you have `…\mods\JLFactDump\init.lua`).
2. Launch the game. Press **`~`** to open the CET overlay. You should see a **"JL Fact Dump"**
   window. It shows a "Hooks:" line and live counters.
3. Open **Bindings** (in the CET overlay) → find the **Hotkeys** section → bind keys to:
   - `Marker: 1) The Heist complete`
   - `Marker: 2) V gets shot (No-Tell Motel)`
   - `Marker: 3) Love Like Fire / Johnny memories`
   - `Marker: 4) Playing for Time starts`
   Pick 4 keys you'll remember (e.g. F1–F4). These let you mark moments **during cutscenes**
   without opening the overlay.

## Part 2 — VALIDATE before the costly run (2 minutes, do NOT skip)
The logger tries to hook the game's fact system. On some builds that hook may not attach — we must
confirm it captures BEFORE you spend a whole Heist run.
1. In the JL Fact Dump window, click **"Self-test"**. Open
   `…\mods\JLFactDump\factdump.log` in a text editor → you should see a line ending
   `jlfd_selftest=…`. (This proves file logging works.)
2. Now the real test: do any small in-game action that changes a fact — **loot an item, finish a
   tiny objective, or skip time**. Re-open `factdump.log`. If you see **new `SET` lines** appear,
   the hook works → continue to Part 3.
3. **If NO new `SET` lines appear on a real change** (only your self-test line), this build can't
   hook the native setter. → Use the **Fact Finder fallback** (Part 5) instead.

## Part 3 — Capture the Heist ending
1. Load your **before-the-Heist-ends** save. (The logger wipes `factdump.log` fresh on each game
   load — that's fine.)
2. Play the vanilla ending normally. As each moment happens, **press its marker hotkey once:**
   - **1** the instant the Heist shows as complete / the objective ticks over,
   - **2** when Dex shoots V at the No-Tell Motel,
   - **4** when "Playing for Time" begins (V in the landfill / apartment),
   - **3** later, if/when "Love Like Fire" (Johnny's memory mission) starts.
   Chronology is usually 1 → 2 → 4 → 3. If you miss one, no problem — use a spare marker or just
   note roughly where it was; the timestamps still order everything.
3. Once "Playing for Time" is underway, you're done capturing.

## Part 4 — Analyse on the Mac
1. Copy `…\mods\JLFactDump\factdump.log` to the repo (or anywhere) on the Mac.
2. Run:
   ```
   python3 tools/factdiff/factdiff.py /path/to/factdump.log
   ```
   (No argument = it reads `mod/JLFactDump/factdump.log`.)
3. **Send me the output.** I'm looking for a fact that flips in the **"Heist complete"** segment
   (the Watson lever) that is NOT part of the Johnny/Relic set — that decides whether we can open
   the world without triggering the death/Johnny tail.

## Part 5 — Fallback: Fact Finder (only if Part 2 step 3 failed)
1. Install **Fact Finder** (Nexus mod 12735) — the maintained fact-watching tool.
2. Enable its change-logging (its in-overlay settings; it can log facts as they change).
3. Do the same Heist-ending run, noting the four moments.
4. Send me its log/output file — I'll adapt `factdiff.py` to its format in one pass.

---

**Safety:** setting facts out of order can soft-lock quests, so we are ONLY *reading/watching* here.
Keep a backup save. Nothing in this spike writes to your story state except the harmless
`jlfd_selftest` fact.
