# Research — "Save Jackie" main-quest freeze / no-Johnny route (2026-07-06)

Feasibility research for the **alternate-timeline "save Jackie" route** (a separate mode from the
existing quiet-life layer): the player fights an authored escape at the Heist (kill Smasher, roof,
kill Takemura, helicopter with a *surviving* Jackie), fades to black, and wakes at Vik's — with the
whole Relic/Johnny plot and Jackie's death never happening, but the open world unlocked.

Three parallel research passes (patch 2.3/2.31, PC + CET). Confidence + sources inline. **Every
undocumented item below must be verified live via the JLFactDump spike (`mod/JLFactDump/SPIKE.md`)
before we build on it.**

## Quest map (confirmed, high confidence)
- The Pickup `q003_maelstrom` → The Information `q004_braindance` → **The Heist `q005_heist`** →
  **Playing for Time `q101_resurrection`** (Act 2 opener). Love Like Fire = `q101_01_firestorm`.
- Source: wiki.redmodding.org reference-quest-ids.

## Where the death/biochip/Johnny live (the interception boundary)
- Biochip install + Jackie's death + **Dex shooting V are all in the TAIL of `q005_heist`** (Konpeki
  escape → Delamain cab → No-Tell Motel → Dex). [high]
- **Johnny's engram, the "fused chip," and V's terminal-condition framing all begin at `q101`.** [high]
- So the freeze point is clean: intercept the `q005` tail *before* the cab-death sequence; never
  enter `q101`. Sources: cyberpunk.fandom.com The Heist / Relic / Playing for Time; powerpyx PfT.

## 1. Watson lockdown — the hard finding
- The lockdown is **welded to The Heist's completion** via an internal "Lockdown" quest that
  auto-completes when the Heist ends. [medium-high] Source: nexus 23219 (LONGER LOCKDOWN — extends
  exactly this).
- **No documented standalone fact** lifts it; the CET useful-commands list, redmodding facts page,
  and command roundups contain no Watson/skip-prologue command. [high]
- **All "free-roam without the story" precedent ships as pre-made SAVEGAMES**, not fact flips
  (nexus 311 "Skip To Act 2", 22068, 10398, 16669). Strong signal there is no known clean runtime
  lever. [high]
- The barrier is **placed "prevention"/invisible-wall areas** (players physically drive out through
  North Oak gaps) — quest-node logic, not a world-streaming flag. [medium-high]
- **Implication:** the exact lockdown lever is undocumented → **find it live** (the spike). If it
  turns out to be genuinely inseparable from `q101`, fallback is a WolvenKit `.questphase` edit to
  complete the Lockdown quest / neutralize its prevention areas directly.

## 2. Freezing the main quest safely
- **No dedicated "freeze the story" mod exists.** Nearest precedent = save-based Act-1 parks and the
  Act-1 *extension* mod (23219). [medium]
- **Leaving The Heist Active forever does NOT corrupt saves** — the old save-corruption bug was the
  patched 8 MB file-size issue, unrelated to quest state. Real risk = quest-state **soft-lock**. [high]
- **Biggest cost of freezing pre-Heist:** most fixers/gigs, the apartment, many vendors, romances,
  and the wider map only unlock in Act 2 → a **sparse Watson-only sandbox**. This is why the literal
  "never complete the Heist" path is self-defeating, and we chose the intercept-the-tail route. [high]
- **Cleanest freeze = behavioral + journal untrack**, not fact-editing:
  - `gameJournalManager.UntrackEntry()` / `IsEntryTracked()` — untrack without completing.
    Source: Angelore/simpleUntrackQuest reds.
  - **Untrack Quest Ultimate (nexus 6328)** ships a "Main Quest re-tracking preventer," is
    **2.31-safe** and already **inactive during Prologue** — directly reusable pattern. [high]
  - `gameJournalManager.ChangeEntryState(...)` with `gameJournalEntryState` (Active/Inactive/
    Succeeded/Failed) — exact signature **unverified**, confirm in NativeDB. [medium]
- **Prevent Act-2 quests auto-starting:** cleanest is don't satisfy the start (trigger-gate) or a
  WolvenKit `.questphase` edit at the transition node; **holding a start fact at 0 is a last resort**
  (the wiki explicitly warns fact edits "almost always cause additional problems much later").

## 3. Johnny — no clean post-hoc disable, so freeze BEFORE it
- **No master "johnny_active"/"disable_johnny" fact.** Presence is spread across many quest scenes
  + independent systems. [medium-high]
- "Disable Johnny" mods only **mute audio** (SHUT UP Johnny 15783) or **surgically delete single
  appearances** (Remove Passenger Johnny 18451/21469; No Johnny in apartment 21911); glitch removal
  (832) is cosmetic. **None flips a fact; none prevents story Johnny.** [high]
- The **only** clean surface is the **patch-2.2 systemic passenger Johnny** (script-driven → can be
  disabled at source, e.g. The Passenger — Feature Settings 18380, chance 0). [high]
- **Confirms our architecture:** freezing before `q101` means quest-Johnny + the terminal-condition
  framing never author in. And if Act 2 never begins, **virtually all "dying"/Relic world content
  can't fire** (it's gated behind Act-2 progress + post-Heist district unlocks). Residual risk =
  Act-1 Watson content only; spot-check early Regina gigs / Watson hustle barks. [high/medium]

## CET fact API (for the spike + later)
- Set: `Game.GetQuestsSystem():SetFactStr("name", int)` · Read: `GetFactStr("name")` (0 if unset).
  Facts are signed ints, default 0, persist in the save. [high] Source: CET wiki "how-do-i".
- **CET cannot "fix" a stuck quest** — don't rely on facts to un-stick an accidentally-advanced
  quest. [high]

## Open items to resolve live (the spike answers these)
1. The exact fact/quest that lifts the Watson lockdown, and whether it's separable from `q101`.
2. The precise `q005` phase/node where the cab-death tail begins (WolvenKit, for the interception).
3. Confirm `q101` can be held off (trigger-gate vs. `.questphase` gate).
4. `gameJournalManager.ChangeEntryState` signature + CET JournalManager accessor (NativeDB).

## Key sources
- Quest facts model + "editing facts breaks things later" warning: wiki.redmodding.org/…/quests-facts-and-files
- CET fact API + "can't fix stuck quests": wiki.redmodding.org/cyber-engine-tweaks/console/console/how-do-i
- Quest IDs: wiki.redmodding.org/…/reference-quest-ids
- Untrack mechanism: github.com/Angelore/simpleUntrackQuest ; re-track preventer nexus 6328
- Lockdown welded to Heist / Act-1 extension: nexus 23219 ; Act-2 skip saves: nexus 311, 22068, 16669
- Disable-Johnny mechanisms: nexus 15783, 18451, 21469, 21911, 832, 18380
- Fact-watching tools: Fact Finder nexus 12735 (maintained) ; Fact Log 7389 (deprecated/broken)
