# SPIKE — find the Watson-unlock lever (and confirm the Johnny split)

**Goal of this experiment:** on YOUR real game, capture exactly which quest state flips when the
Heist ends, so we can find the lever that opens the world (Watson lockdown) **and** confirm the
Johnny/Relic state we must never trigger. These names are undocumented, so we record them live.

This is **observation only** — you play the *vanilla* Heist ending on a throwaway save and just
watch. We change nothing yet. Do it on a **backup/disposable save** anyway.

> **What changed in v2 (why the first run looked empty).** The first log only caught shallow
> world-reaction facts (`wanted_level`, `ripperdocs_visited`, `delamain` calls) because it only
> hooked `SetFact` — but the main quest (Heist tail, Watson lift, Jackie's death, Johnny/Relic)
> advances through the **quest graph + journal**, which never pass through `SetFact`. So the tool
> was structurally blind to the levers. **v2 adds two channels that see that layer:**
> - **`journal`** — hooks `gameJournalManager:ChangeEntryState`, the real main-quest state machine
>   (Heist → Succeeded, the Lockdown quest completing, Playing for Time going Active).
> - **`poll`** — every ~0.75s it *reads* a curated suspect list of fact names and logs any that
>   change, catching graph-set facts a write-hook can't see.
>
> You'll see three `src` tags in the log now: `journal`, `poll`, and the old `cname`/`str` writes.

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
2. Launch the game. Press **`~`** to open the CET overlay. You should see a **"JL Fact Dump v2"**
   window. It shows a "Hooks:" line and live counters (Writes / Journal / Poll changes / Markers).
   For the run to be useful the Hooks line should list **`gameJournalManager:ChangeEntryState`** —
   that's the journal channel. If it's missing, tell me and I'll adjust the class spelling.
3. Open **Bindings** (in the CET overlay) → find the **Hotkeys** section → bind keys to:
   - `Marker: 1) The Heist complete`
   - `Marker: 2) V gets shot (No-Tell Motel)`
   - `Marker: 3) Love Like Fire / Johnny memories`
   - `Marker: 4) Playing for Time starts`
   Pick 4 keys you'll remember (e.g. F1–F4). These let you mark moments **during cutscenes**
   without opening the overlay.

## Part 2 — VALIDATE before the costly run (2 minutes, do NOT skip)
The logger tries to hook two systems. On some builds a hook may not attach — confirm capture BEFORE
you spend a whole Heist run.
1. In the JL Fact Dump v2 window, click **"Self-test"**. Open
   `…\mods\JLFactDump\factdump.log` in a text editor → you should see a line ending
   `jlfd_selftest=…`. (This proves file logging works.)
2. Now the real test: do a small in-game action that moves the story a hair — **finish a tiny
   objective / advance a quest step, loot something, or skip time**. Re-open `factdump.log`. The
   **journal channel is the one that matters** — advancing an objective should add a line like
   `SET  journal  <class>#<hash>=Active/1` (or `Succeeded/2`). Seeing **any** new `journal` line on
   a real story action means the key channel works → continue to Part 3.
   - `poll` lines only appear when a *watched* fact flips, so you may not see one from a random
     action — that's fine. A `journal` line is the pass condition.
3. **If NO `journal` line ever appears** (even after advancing an objective) and the Hooks line
   doesn't list `ChangeEntryState`, the journal hook didn't attach → tell me the exact Hooks line
   and I'll fix the class name, or fall back to **Fact Finder** (Part 5).

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
3. **Send me the output** (or just the raw `factdump.log`). I'm looking for state that flips in the
   **"Heist complete"** segment (the Watson lever) that is NOT part of the Johnny/Relic set — that
   decides whether we can open the world without triggering the death/Johnny tail. With v2 the
   strongest signal is the `journal` lines that go `Succeeded` right at marker 1, plus any `poll`
   fact that moves there.

> **Tip — grow the suspect list.** The `poll` channel only watches the names in the `SUSPECTS`
> table at the top of `init.lua`. If you run **Fact Finder** alongside and spot a fact flipping at
> the Heist end, add its name to that table and re-run — reading an unknown name is harmless (it
> just returns 0), so over-seeding costs nothing.

## Part 5 — Fallback: Fact Finder (only if Part 2 step 3 failed)
1. Install **Fact Finder** (Nexus mod 12735) — the maintained fact-watching tool.
2. Enable its change-logging (its in-overlay settings; it can log facts as they change).
3. Do the same Heist-ending run, noting the four moments.
4. Send me its log/output file — I'll adapt `factdiff.py` to its format in one pass.

---

**Safety:** setting facts out of order can soft-lock quests, so we are ONLY *reading/watching* here.
Keep a backup save. Nothing in this spike writes to your story state except the harmless
`jlfd_selftest` fact.
