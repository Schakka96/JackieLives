# Blaze of Glory — real WolvenKit quest objectives (MVP-B)

MVP-A already runs the whole set-piece and shows the objectives as **native on-screen
message-band text** (the blue notice band). That's a *placeholder*. This doc is how we
replace it with **real journal objectives** — the proper quest name + ticking checkboxes
in the top-right HUD tracker, with the "Quest updated" chime.

## Reality check first (ground rule #1)

Fully-custom tracked journal objectives are one of the **harder** things in CP2077
modding — more involved than everything in MVP-A. But it's very doable, and the plan below
splits it so **you** hand-author the quest text in WolvenKit (the part you asked to do) and
**I** wire the code that flips each objective on/off. We finalize the one exact API call
together on Windows once your `.journal` loads.

The architecture:

```
 your custom .journal  ──packed in the mod archive──►  loaded by the game
        │                                                     ▲
        │  defines: quest "Blaze of Glory" + N objectives      │ driven at runtime by
        ▼                                                       │ JournalManager:ChangeEntryState(...)
   objective paths  ───────────────────────────────────────────┘   (called from our init.lua)
```

## Part 1 — author the quest (WolvenKit, your part)

You'll make one small `.journal` file that declares the quest and its objectives. Nothing
here touches the base game's quests, so it can't break the main story.

1. Open **WolvenKit** and your JackieLives mod project (the same one used for the voice bank).
2. **Tools → Import/Export** isn't needed. Instead, right-click your project's **archive**
   (raw files) tree → **Add → New file → Journal (`.journal`)**. If WolvenKit's version
   doesn't offer a journal template, create a text/JSON resource and we'll convert it — tell
   me and I'll give you the raw skeleton to paste.
3. Save it at this path inside the project (path matters — the game reads journals from here):
   ```
   base\quest\secondary_quests\blaze_of_glory.journal
   ```
   (Any name is fine; remember the exact path — the code needs it.)
4. In the journal editor, build this tree (these are the entries the code will flip):
   - **Quest**: `title = "Blaze of Glory"`  — give it a stable **id/secret hash** (WolvenKit
     shows an `id` field per entry; write the numbers down for each one).
   - **Objective** child: `"Kill Adam Smasher"`
   - **Objective** child: `"Kill Goro Takemura"`
   - **Objective** child: `"Reach the extraction VTOL"`
5. For each entry, note its **`id` (hash)** and its **class name** (quests are
   `gameJournalQuest`, objectives are `gameJournalQuestObjective`). Paste that list back to me
   — that's all I need to drive them.
6. **Pack** the project (WolvenKit → Pack/Install, or just Pack to the `.archive`) and drop the
   resulting `.archive` into the mod's `archive\pc\mod\` folder so `deploy.ps1` ships it.

> If step 2/4's journal editor is missing or fiddly in your WolvenKit build, stop there and
> send me a screenshot — I'll hand you a ready-made raw `.journal` (JSON) to paste and pack,
> so you don't lose time fighting the editor.

## Part 2 — drive the objectives from our code (my part)

Everything the game needs to *show and tick* those objectives is done from **one place** in
`init.lua` — the two Blaze helpers bound in `onInit`:

```lua
-- MVP-A (now): placeholder message band
objective = function(text, dur) showOnscreenMsg(text, dur or 8.0) end,
fade      = function(caption)   showOnscreenMsg(caption or "CUT TO BLACK", 8.0) end,
```

For MVP-B these become calls into `Game.GetJournalManager()`. The shape (we confirm the exact
signature against your loaded journal on Windows):

```lua
-- pseudo — real ids/classes come from your .journal (Part 1, step 5)
local function jSet(entryHashOrPath, className, state)   -- state: Active | Succeeded | Inactive
  local jm = Game.GetJournalManager()
  local entry = jm:GetEntry(entryHashOrPath)             -- exact getter TBD on Windows
  if entry then jm:ChangeEntryState(entry, className, state, gameJournalNotifyOption.Notify) end
end
```

Then `blaze.lua` doesn't change at all — its `pushObjective()` calls already fire at exactly
the right moments (quest start, Smasher down, escape unlocked). I just repoint `objective`/
`fade` from the message band to `jSet(...)` per stage. That's the whole swap.

## What I need from you to finish MVP-B

1. The `.journal` packed and loading in-game (Part 1).
2. The list of **entry ids + class names** for the quest and its 3 objectives.
3. One quick Windows session to confirm the `GetEntry`/`ChangeEntryState` call against your
   journal — then the real HUD objectives light up and the placeholder is gone.

If custom journals turn out to fight us, the fallback that still looks native is a **custom
HUD objective panel drawn by CET** (many mods do this) — less "real quest," but no WolvenKit
and fully in our control. We only fall back if Part 1 proves painful.
