# Shards — how they work now

**The WolvenKit-GUI procedure that used to be in this file is retired.** Nothing about a shard
needs the WolvenKit *editor* any more; the whole thing is text files plus one command-line build.
The reasoning, with sources, is in `docs/research/journal_quests_and_shards_spec.md` §5.

---

## What a shard is made of

A shard is four independent things, and only the last one is hard:

| | what | where it lives | who writes it |
|---|---|---|---|
| the **words** | the note itself | `mod/JackieLives/storyboard.lua`, in a beat's `shard = { ... }` block | you / Claude, as prose |
| the **readable entry** | a `gameJournalOnscreen` node | `archive/source/mod/jackielives/journal/jackielives_quests.journal.json` | **generated** |
| the **item** | the thing in V's Shards tab | `tweaks/JackieLives/jl_shards.yaml` (this folder) | **generated** |
| the **object in the world** | a physical shard case you walk up to | a `.streamingsector` | **not shipped** — see below |

"Generated" means: **never edit those files.** Edit the storyboard and run

```bash
python3 tools/gen_journal_quests.py
```

which rewrites all of them from the one source, and refuses to finish if the Lua and the archive
would disagree about a single path.

---

## The five-minute version

1. Write the shard in `storyboard.lua` on the beat that gives it:

   ```lua
   shard = {
     id = "arc_scan",                                  -- permanent; saves store it
     title = "Ripperdoc scan — patient: J. Welles",
     author = "Viktor Vektor",
     body = { "first paragraph", "", "second paragraph" },   -- "" = a blank line
   },
   ```

2. `python3 tools/gen_journal_quests.py` (Mac, no game needed).

3. On Windows: `python tools\build_archive.py`, then copy
   `mod/JackieLives_shards/tweaks/JackieLives/jl_shards.yaml` to
   `<game>\r6\tweaks\JackieLives\`.

4. In game, `JQuest.shard(...)` puts it in V's Shards tab and makes it readable. With no archive
   installed it degrades to the on-screen text band — never to nothing.

---

## Why it used to be hard, and the four things the old hand-written YAML got wrong

All four cost a session each to find, and none of them is guessable:

1. **`itemSecondaryAction` is the line the whole shard hangs off.** It names an ItemAction record
   whose `journalEntry` flat is the path of the readable entry. All 335 vanilla shards are built
   this way. Without it you have an item that cannot be read.
2. **`objectActions` is a different property and is NOT the read action.** Vanilla's is
   `[Drop, Disassemble]`. Overriding it costs the player Disassemble and buys nothing.
3. **The title the player sees** — on the loot prompt under the crosshair, and in the scanner —
   **is the journal entry's title, not the item's `displayName`.** The vanilla shard's
   `displayName` is empty and it still shows a title. `displayName` only names the inventory row.
4. **`displayName` takes a BARE localization key** (`jl_j_s_arc_scan_item`), never
   `LocKey#jl_j_s_arc_scan_item`. ArchiveXL treats a `LocKey#` prefix as "this is already a
   numeric id, leave it alone", so a prefixed *name* renders on screen as raw text. The old
   version of this file had exactly that bug.

Plus two more the old file carried: `entityName: w_data_shard` and `removeAfterUse: False` are not
in either shipped recipe, and `removeAfterUse` is not a field on `gamedataItemAction_Record` at
all. Both are gone.

The old journal path (`.../minor_quest/new_shards/shards/...`) was invented. The real shelf,
read out of the shipped game's own journal, is:

```
onscreens/emails/quests/minor_quest/jl_shards/shards/<shard id>
```

---

## What is deliberately NOT shipped: the physical shard case

A shard case you can walk up to and loot is a node baked into a `.streamingsector`. ArchiveXL
cannot add a node to a sector the game already ships, so it means shipping our own sector, and the
node has to carry a full base-game reference hash (an unnamed node does not load at all) plus 53
fields of container instance data lifted off a vanilla sector. That is the real work in the shard
feature and it is a separate project.

Until then the shard arrives the way the game itself does it when it hands you a note: it goes
into V's Shards tab and becomes readable. `readAction.script` shows that the "make it readable"
step is a single journal state change — the item only exists so a player can *pick it up*.

Same reason there are no map pins in v1: a quest pin needs a base-game anchor node plus an exact
offset, it is computed while V may be across the city, and once shown it cannot be un-shown.

---

## Files in this folder

| file | what |
|---|---|
| `SHARD_SHEET.md` | this page |
| `tweaks/JackieLives/jl_shards.yaml` | **generated** — the item + read-action record for every shard; deploys loose to `<game>\r6\tweaks\JackieLives\` |

The old `shards.json` tracker and `localization/jl_shards*.json` are gone: the tracker's contents
are now derivable from `mod/JackieLives/journalquest_index.lua`, and the words moved into the
storyboard and the generated localization resource (English *and* the existing Japanese, which was
carried across verbatim into `tools/journal_text/ja-jp.txt`).
