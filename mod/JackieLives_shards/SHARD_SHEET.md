# 🗂️ SHARD SHEET — `jl_shard_badlands_note` (TESTER)

**Jackie's note to V at the Badlands hideout (Rocky Ridge garage).**
This is the hand-off doc: Claude authored everything text; you do the WolvenKit part.
Follow it top to bottom. Copy the **exact** values in the boxes — don't retype from memory.

---

## What Claude already did (files in `mod/JackieLives_shards/`)
| File | What it is | Where it deploys |
|------|-----------|------------------|
| `tweaks/JackieLives/jl_shards.yaml` | TweakXL item + read-action records | copy to `<game>\r6\tweaks\JackieLives\` (loads loose, no WolvenKit) |
| `localization/jl_shards.json` | the shard's actual words (title + body) | you import this into your WolvenKit project (Step 3) |
| `shards.json` | tracker (what exists / where / status) | stays in the repo |

**The words on the shard are in `jl_shards.json` — to reword the shard later, Claude edits that file. You never touch WolvenKit again for wording.**

---

## The 4 values you'll paste (the "shard sheet")
| Field | Value (copy exactly) |
|-------|----------------------|
| **journalEntry path** | `onscreens/jackielives/jl_shard_badlands_note` |
| **onscreen entry `id`** | `jl_shard_badlands_note` |
| **`title` LocKey** | `LocKey#jl_shard_badlands_note_title` |
| **`description` LocKey** | `LocKey#jl_shard_badlands_note_desc` |
| **`tag`** | `articles` |

That `journalEntry` path is not one field — it's the **chain of ids** you build in the journal tree:
`onscreens` → `jackielives` → `jl_shard_badlands_note`. Step 2 builds exactly that chain.

---

## Step 0 — make a WolvenKit project (once)
1. Open WolvenKit → your JackieLives project (or **File ▸ New Project** → name it `JackieLives_shards`).
2. This project will hold **two files**: the journal (Step 1–2) and the localization (Step 3). Then you install it (Step 4).

## Step 1 — create the journal file
1. In **Project Explorer** (left), right-click the project's `archive` root ▸ **Add ▸ New File…**
2. In the type search, type **`journal`** and pick **`JournalResource`** (a "Journal" / `gameJournalResource`).
3. Name it: **`base\journal\jackielives\jl_shard_badlands_note.journal`**
   (type that whole path as the name; WolvenKit makes the folders). Click **Create** — it opens in the editor.

## Step 2 — build the entry chain (this is the fiddly bit — go slow)
You're recreating this nesting so the game can find the entry by the path in the box above:

```
gameJournalResource (root)
└─ entry: gameJournalOnscreenRoot        id = "onscreens"
   └─ children: gameJournalContainerEntry id = "jackielives"
      └─ children: gameJournalOnscreen    id = "jl_shard_badlands_note"   ← the shard
```

1. Click the root. Find its **`entry`** field → it holds a `gameJournalRootFolderEntry` with a **`children`** array. (If `entry` is empty, right-click it ▸ set to `gameJournalRootFolderEntry`.)
2. In that **`children`** array: right-click ▸ **Add Item** ▸ choose **`gameJournalOnscreenRoot`**. Set its **`id`** = `onscreens`.
3. On that `onscreens` node, open its **`children`** array ▸ Add Item ▸ **`gameJournalContainerEntry`**. Set **`id`** = `jackielives`.
4. On `jackielives`, open its **`children`** array ▸ Add Item ▸ **`gameJournalOnscreen`**. This is the shard. Set:
   - **`id`** = `jl_shard_badlands_note`
   - **`title`** → its value = `LocKey#jl_shard_badlands_note_title`
   - **`description`** → its value = `LocKey#jl_shard_badlands_note_desc`
   - **`tag`** = `articles`
5. **Ctrl+S** to save.

> 🧭 If a field name looks slightly different in your WolvenKit version (e.g. `entries` vs `children`), the SHAPE is what matters: root → an onscreen-root id `onscreens` → a container id `jackielives` → an onscreen entry id `jl_shard_badlands_note`. Send Claude a screenshot of the tree if unsure — that's faster than guessing.

## Step 3 — add the localization (the words)
1. Right-click the project `archive` root ▸ **Add ▸ New File…** ▸ search **`json`** ▸ pick **`JsonResource`**.
2. Name it: **`base\localization\jackielives\jl_shards.json`**
3. Open Claude's `mod/JackieLives_shards/localization/jl_shards.json`, **copy its whole contents**, and paste over the new file's contents in WolvenKit (Raw/text view). Save.
   - It has 3 entries by `secondaryKey`: `..._title`, `..._desc` (the note body), `..._name` (inventory name).

## Step 4 — install to game
1. Copy Claude's **`tweaks/JackieLives/jl_shards.yaml`** to **`<game>\r6\tweaks\JackieLives\jl_shards.yaml`**.
2. In WolvenKit: **Install to game** (or Pack ▸ then drop the packed `.archive` into `<game>\archive\pc\mod\`).
   This ships the journal + localization.
3. Make sure **TweakXL**, **ArchiveXL**, **RED4ext** are installed (they already are for JackieLives).

## Step 5 — TEST (Milestone 1: does it READ?)
This proves the whole chain (item → action → journal → words) before we bother placing it in the world.
1. Launch the game, load a save. Open the CET console.
2. Run: `Game.AddToInventory("Items.jl_shard_badlands_note", 1)`
3. Open your inventory ▸ **Shards** tab ▸ find **"Shard: Jackie Welles"** ▸ read it.
4. ✅ **Pass** = you see the title and Jackie's note text.
   ❌ If it shows raw `LocKey#jl_shard_badlands_note_desc` = the localization didn't link → tell Claude
   (we switch to numeric LocKeys). ❌ If the item doesn't appear = the item record/tags → tell Claude.

**Report back and Claude updates `shards.json` `displaysCorrectly: true`.**

---

## Milestone 2 — place it at the Badlands coord (AFTER it reads)
Coord is already captured: **`x 2575.852, y 0.291, z 80.871`, yaw 129.8** (Rocky Ridge garage).

⚠️ **Honest note (feasibility):** hand-writing the `.streamingsector` that drops a physical shard-case at a
coord is the one genuinely finicky part — the reliable beginner path is **World Builder** (Nexus 20660):
fly to the spot in-game, drop a `shard` / `container` prop, export, and WolvenKit's import script bakes the
sector. Claude will write the step-by-step for that once Milestone 1 passes — no point building placement
around a shard that doesn't read yet. (Until then, the shard is fully usable via the retrieval questline's
existing proximity trigger, which already fires at these exact coords.)
