# The journal probe — one in-game test, on Windows

**What you're testing:** whether JackieLives can put a *real* quest objective in the game's own
tracker — the box in the top right with the chime, the one every vanilla quest uses — instead of
the plain text band the mod draws itself today.

**Why it needs testing at all.** Every individual piece of this is confirmed: the game's journal
can be extended by a mod, the tracker can be driven from Lua, and the format of the file we ship
is read straight out of the shipped game. What has never been *observed* is the combination —
a quest that exists only as journal data, with no quest-graph behind it, driving the HUD. That is
one experiment with a yes/no answer, and this is it. Everything else in the feature is already
built and waiting on the result.

Budget: about ten minutes, one game load.

---

## Vocabulary (three words, then it's plain English)

- **archive** — a `.archive` file is how a mod adds *data* to the game (as opposed to *code*). Our
  quests and the text of Jackie's shards live in one. It is built on Windows, by a command.
- **the journal** — the game's own database of quests, shards, contacts and codex entries. It is
  data, not code, which is why a mod can add branches to it.
- **objective** — one line in the tracker ("Take Jackie to Vik"). The tracker shows objectives, not
  quests, which turns out to matter a lot.

---

## Before you start

On the **Mac**, make sure the generated files are current (this reads the story and rewrites the
quest data from it — it needs no game):

```bash
python3 tools/gen_journal_quests.py
lua tools/test_journalquest.lua      # 48 checks, must say 0 failed
lua tools/loadsim.lua                # must say 0 failed
```

Push, and pull on the Windows box.

---

## Step 1 — build the archive (Windows, once)

```
cd <the JackieLives repo>
python tools\build_archive.py
```

> ⚠️ **This only works once the `.archive.xl` lists the two new files.** The build script itself
> needs no change — it discovers whatever is under `archive/source/` — but the `.xl` is the manifest
> that tells the game what to merge, and it is hand-maintained. The exact two blocks are written out
> in `journal_quests_and_shards_spec.md` under **"Handoff — changes owed to build_archive.py and the
> .xl"**. If someone has already added them, this step is just the command above.

**How to know it worked:** the command prints the files it packed. `jackielives_quests.journal`
and `jackielives_questtext.json` must both be in that list. If they aren't, stop — the rest of the
test cannot tell "the feature doesn't work" apart from "the data never shipped", and that
ambiguity is exactly what wastes an evening.

Copy the built archive to the game as you normally do (`deploy.bat`), and also copy

```
mod\JackieLives_shards\tweaks\JackieLives\jl_shards.yaml
```

to

```
E:\SteamLibrary\steamapps\common\Cyberpunk 2077\r6\tweaks\JackieLives\
```

(That one is a loose file — no build step. It is only needed for the shard half of the test.)

---

## Step 2 — load a save and press one button

1. Load any save where the mod already works (Jackie found, mod unlocked). **Not** a save you'd be
   sad to lose — this should be harmless, but "should be" is doing work in that sentence.
2. `Esc` → `Settings` → `Jackie Lives` → **Ghost in the Machine**.
3. Press **Check** on *"Check the quest journal"*.
4. Close the menu and **look at the top right of the screen.**

The button clears any previous run, then activates the first objective of the story and asks the
game to track it. It deliberately **leaves it on screen** — the thing you are looking for *is* the
evidence. When you're done, press **Clear** on the row below it.

---

## Step 3 — read the two answers

### Answer A: your eyes

**Pass looks like:** the quest tracker appears in the top right, headed **Ghost in the Machine**,
with one line under it: **Take Jackie to Vik**. Probably with the usual chime.

### Answer B: the log

Open `jackie_debug.log` in the game folder and look at the last `[JQuest]` line. It looks like:

```
[JQuest] JQuest probe [ghost/p1/take_jackie_to_vik] archive=true | before: quest=Inactive phase=Inactive obj=Inactive | after:  quest=Active phase=Active obj=Active tracked=true trackedIsOurs=true pushed=true | shard arc_scan=Inactive
```

Read it left to right:

| field | what it means |
|---|---|
| `archive=true` | the game can see our quest data at all. **`false` = the archive isn't installed or is stale — nothing after this means anything.** |
| `before:` | what the states were before the button. On a first run all three should be `Inactive`. |
| `quest= phase= obj=` | after the press. **All three must say `Active`.** The tracker filters on "active" at every level, so an active objective under an inactive quest is invisible. |
| `tracked=true` | the game is tracking *something*. |
| `trackedIsOurs=true` | it's tracking *our* objective and not a quest you already had running. |
| `pushed=true` | our code believed the whole chain succeeded. |

---

## Step 4 — what each outcome means, and what to do

| what you saw | what it means | next |
|---|---|---|
| Tracker on screen + all `Active` + `trackedIsOurs=true` | **The feature works.** The last unknown is closed. | Ship it: wire the story's beats to it and delete the on-screen band fallback path from the design. |
| `archive=false` | The data never reached the game. Not a verdict on the feature. | Re-check step 1: was the patch applied, were both files in the packed list, did the archive get copied? |
| All three `Active`, but **nothing on screen** | The API works and the *display* is failing. Prime suspect is the quest's title: the tracker refuses to draw a container whose title is empty, and a title that failed to resolve reads as empty. | Look for the title showing as raw text (like `LocKey#12345`) anywhere in the journal menu. If so, the localization file didn't merge — the `.xl` list entry (handoff note) is the thing to check. |
| `quest=Active` but `phase=Inactive` or `obj=Inactive` | A path in our data doesn't match a path in the archive. | On the Mac: `python3 tools/gen_journal_quests.py` then `lua tools/test_journalquest.lua`. If those pass, the archive on Windows is stale — rebuild. |
| `tracked=true` but `trackedIsOurs=false` | The game overrode our tracked entry with the player's own current quest. | Not a failure of the mechanism, only of the timing. Note it and move on — the real feature tracks at a story beat, not from a settings menu. |
| `no-journal-manager` | You pressed it from the main menu, not in a loaded game. | Load a save first. |
| Nothing at all in the log | The button didn't run. | Check the log's start-up lines for a load error. |

**Whatever happens, the mod is not damaged.** Every journal call is written to fail quietly and
fall back to the on-screen text band the mod has always used. A failed probe means "we don't get
the pretty tracker", never "the mod is broken".

---

## Optional: the shard half (two more minutes)

Same session, after the quest test. In the CET console:

```
Game.AddToInventory("Items.jl_shard_arc_scan", 1)
```

**Pass:** it appears in `Inventory → Shards`, and opening it shows Vik's scan of Jackie —
"PATIENT: Welles, J. — post-trauma review, 14 months." — with the paragraph breaks intact.

**If the shard is there but its text is empty or reads as raw `LocKey#...`:** the item records
loaded (that's the loose `.yaml`) but the archive's text didn't. Same suspect as above — the `.xl`
localization list.

**If the item doesn't exist at all:** the `.yaml` isn't in `r6\tweaks\JackieLives\`, or TweakXL
isn't installed. That's the loose-file copy in step 1, nothing to do with the archive.
