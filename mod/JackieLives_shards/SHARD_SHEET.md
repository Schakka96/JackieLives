# 🗂️ SHARD SHEET — `jl_shard_badlands_note` (TESTER)

**Jackie's note to V at the Badlands hideout (Rocky Ridge garage).**
This is the hand-off doc: Claude authored everything text; you do the WolvenKit part.
Follow it top to bottom. Copy the **exact** values in the boxes — don't retype from memory.

> ♻️ **Corrected 2026-07-07** after your first attempt. Your NOTEs were right: the journal node types
> I gave were wrong. This version uses the real wiki types (`gameJournalPrimaryFolderEntry` /
> `gameJournalFolderEntry` / `gameJournalOnscreenGroup`) and the correct field name **`entries`**
> (not `children`). It now mirrors the wiki tutorial 1:1, so you can follow that video and only the
> **last entry** is customised to ours.

---

## ✅ Is this a stable, FIXED world shard? — YES (your key question)
**This is a baked, streamed world object — not a runtime spawn.** The physical shard-case (Milestone 2)
lives as a node inside a **`.streamingsector`** that ArchiveXL merges into the game's world streaming.
That means the game's **streaming system** — the exact same one that loads every vanilla prop, container,
NPC and vanilla shard — brings it in from the map data at fixed coordinates. It does **not** run any Lua
`spawn` call when V approaches; nothing "drops into existence in the air."

- The object's existence + position are **baked into world data**, identical to how CDPR ships shards.
- Streaming load/unload by distance is just standard LOD (invisible, stable) — not a proximity script.
- This is precisely why we chose **Route 2 (baked)** over Route 1 (CET runtime spawn), which *would* be the
  unstable "pop in near V" behaviour you're rightly avoiding. We are NOT doing Route 1.

(Milestone 1 below tests only the *readable* item via a console command — that's a test convenience, not how
the shard reaches the player. The shipped shard is the baked world object.)

---

## What Claude already did (files in `mod/JackieLives_shards/`)
| File | What it is | Where it deploys |
|------|-----------|------------------|
| `tweaks/JackieLives/jl_shards.yaml` | TweakXL item + read-action records | copy to `<game>\r6\tweaks\JackieLives\` (loads loose, no WolvenKit) |
| `localization/jl_shards.json` | the shard's actual words (title + body) | you import this into your WolvenKit project (Step 3) |
| `shards.json` | tracker (what exists / where / status) | stays in the repo |

**The words on the shard are in `jl_shards.json` — to reword the shard later, Claude edits that file. You never touch WolvenKit again for wording.**

---

## The values you'll paste (the "shard sheet")
| Field | Value (copy exactly) |
|-------|----------------------|
| **journalEntry path** | `onscreens/emails/quests/minor_quest/new_shards/shards/jl_shard_badlands_note` |
| **onscreen entry `id`** (the leaf) | `jl_shard_badlands_note` |
| **`title` LocKey** | `LocKey#jl_shard_badlands_note_title` |
| **`description` LocKey** | `LocKey#jl_shard_badlands_note_desc` |
| **`tag`** | `articles` |

> The `journalEntry` path IS the chain of `id`s you build in Step 2 — it must match exactly, or the
> shard opens to nothing. We keep the wiki tutorial's folder ids (`emails/quests/minor_quest/new_shards/
> shards`) so you can follow the video verbatim; those ids are internal-only (the player never sees them).

---

## Step 0 — make a WolvenKit project (once)
1. Open WolvenKit → your JackieLives project (or **File ▸ New Project** → name it `JackieLives_shards`).
2. It holds **two files**: the journal (Steps 1–2) and the localization (Step 3). Then you install (Step 4).

## Step 1 — create the journal file
1. In **Project Explorer**, right-click the project's `archive` root ▸ **Add ▸ New File…**
2. Type-search **`journal`** ▸ pick **`JournalResource`** (`gameJournalResource`).
3. Name it: **`base\journal\jackielives\jl_shard_badlands_note.journal`**
   (type the whole path; WolvenKit makes folders). Create ▸ it opens in the editor.

## Step 2 — build the entry tree (CORRECTED — matches the wiki video exactly)
Build this nesting. **The field that holds children at every level is `entries`.** At each level you
right-click the parent's **`entries`** array ▸ **Add Item** ▸ pick the **type shown**, then set its **`id`**:

```
gameJournalResource (root)
└─ entry:  gameJournalRootFolderEntry
   └─ entries:
      └─ gameJournalPrimaryFolderEntry   id = "onscreens"      ← MANDATORY top folder
         └─ entries:
            └─ gameJournalFolderEntry     id = "emails"
               └─ entries:
                  └─ gameJournalFolderEntry   id = "quests"
                     └─ entries:
                        └─ gameJournalFolderEntry   id = "minor_quest"
                           └─ entries:
                              └─ gameJournalFolderEntry   id = "new_shards"
                                 └─ entries:
                                    └─ gameJournalOnscreenGroup   id = "shards"
                                       └─ entries:
                                          └─ gameJournalOnscreen  id = "jl_shard_badlands_note"  ← OURS
```

Concretely:
1. Click the **root**. Its **`entry`** field should be a `gameJournalRootFolderEntry`. If empty, right-click
   `entry` ▸ set/assign type `gameJournalRootFolderEntry`.
2. Open that entry's **`entries`** array ▸ **Add Item** ▸ **`gameJournalPrimaryFolderEntry`** ▸ set `id` = `onscreens`.
   *(This is the fix: `gameJournalPrimaryFolderEntry`, NOT `gameJournalOnscreenRoot` — the latter is a leaf with
   no `entries`, which is the wall you hit.)*
3. On `onscreens`, open **`entries`** ▸ Add **`gameJournalFolderEntry`** ▸ `id` = `emails`.
4. On `emails`, **`entries`** ▸ Add **`gameJournalFolderEntry`** ▸ `id` = `quests`.
5. On `quests`, **`entries`** ▸ Add **`gameJournalFolderEntry`** ▸ `id` = `minor_quest`.
6. On `minor_quest`, **`entries`** ▸ Add **`gameJournalFolderEntry`** ▸ `id` = `new_shards`.
7. On `new_shards`, **`entries`** ▸ Add **`gameJournalOnscreenGroup`** ▸ `id` = `shards`.
8. On `shards`, **`entries`** ▸ Add **`gameJournalOnscreen`** ▸ this is the shard. Set:
   - `id` = `jl_shard_badlands_note`
   - `title` → value = `LocKey#jl_shard_badlands_note_title`
   - `description` → value = `LocKey#jl_shard_badlands_note_desc`
   - `tag` = `articles`
9. **Ctrl+S**.

> 🧭 The **types** at each level are what matter (folders must be a *FolderEntry* type that HAS an `entries`
> array; the shard group must be `gameJournalOnscreenGroup`; the leaf is `gameJournalOnscreen`). If you'd
> rather just follow the wiki video and rename its final entry to `jl_shard_badlands_note`, that's identical
> — the video's folder ids match the path above. Screenshot the tree to Claude if anything looks off.

## Step 3 — add the localization (the words)
1. Right-click `archive` root ▸ **Add ▸ New File…** ▸ search **`json`** ▸ pick **`JsonResource`**.
2. Name it: **`base\localization\jackielives\jl_shards.json`**
3. Open Claude's `mod/JackieLives_shards/localization/jl_shards.json`, copy its **whole contents**, paste over
   the new file (Raw/text view). Save. (3 entries by `secondaryKey`: `_title`, `_desc` body, `_name`.)

## Step 4 — install to game
1. Copy Claude's **`tweaks/JackieLives/jl_shards.yaml`** → **`<game>\r6\tweaks\JackieLives\jl_shards.yaml`**.
2. In WolvenKit: **Install to game** (ships the journal + localization archive).
3. Confirm **TweakXL / ArchiveXL / RED4ext** are installed (they already are for JackieLives).

## Step 5 — TEST (Milestone 1: does it READ?)
Proves the chain item → action → journal → words, before we place it in the world.
1. Load a save, open the CET console.
2. Run: `Game.AddToInventory("Items.jl_shard_badlands_note", 1)`
3. Inventory ▸ **Shards** tab ▸ find **"Shard: Jackie Welles"** ▸ read it.
4. ✅ **Pass** = title + Jackie's note show.
   ❌ shows raw `LocKey#jl_shard_badlands_note_desc` = localization not linked → tell Claude (switch to numeric LocKeys).
   ❌ item missing = item record/tags → tell Claude.

**Report back → Claude flips `shards.json` `displaysCorrectly: true`.**

---

## Milestone 2 — place the FIXED shard at the Badlands coord (AFTER it reads)
Coord captured: **`x 2575.852, y 0.291, z 80.871`, yaw 129.8** (Rocky Ridge garage).

This is the baked `.streamingsector` step (see the stability section up top — fixed world object, not a spawn).
⚠️ Hand-writing a streamingsector is the finicky part; the reliable beginner path is **World Builder**
(Nexus 20660): fly to the spot, drop a shard/container prop, export, and WolvenKit bakes the sector. Claude
writes that step-by-step once Milestone 1 passes — no point placing a shard that doesn't read yet.
