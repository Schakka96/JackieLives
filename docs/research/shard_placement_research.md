# Research — Placing real readable shards at fixed coords (TODO feature #2)

_Written 2026-07-03. Corrects an over-cautious first-pass verdict after Antonia pushed on ArchiveXL._

## The goal (Antonia)
"Tell Claude 'place shard X at position Y' and I never touch WolvenKit." Real in-game shards at fixed
coordinates that V walks up to and reads. Plus a tracker tool for what shards exist / where / display
status / last-updated.

## Verdict
**Achievable.** My first pass wrongly anchored on "a tool that edits the `.archive` binary" (which IS not
worth building) and undersold the alternatives. The goal is reachable two ways; **Route 1 hits the exact
"zero-WolvenKit" experience.**

## What a "real" readable shard actually is
From the redmodding wiki *Creating custom shards*:
- **Item record** — `gamedataItem_Record`, `itemType: ItemType.Gen_Readable` (e.g. `Items.new_shards_01_shard`).
- **Action record** — `gamedataItemAction_Record`, with `journalEntry:` pointing at the onscreen entry.
- **`.journal` onscreen entry** — `gameJournalOnscreen` (id/title LocKey/description LocKey/`tag: articles`).
  The record references the content; the content is the localization.
- **Localization JSON** — `localizationPersistenceOnScreenEntry` (femaleVariant text).
- **World object** — a `shard_case_container.ent` placed at the coordinate (the thing V interacts with).

Which of those are plain text (Claude can author) vs binary:
- ✅ item record, action record, localization JSON → **TweakXL YAML + JSON = text, authorable.**
- ❌ the `.journal` onscreen resource → **binary RED resource** (the one genuinely non-text piece).

## Route 1 — CET/Codeware runtime spawn  ★ recommended, zero WolvenKit / zero ArchiveXL
- The mod **already** spawns entities at coordinates (`spawnDynEntity`) and **already** does proximity→text
  (`Config.postShards`, an invisible trigger + `showTip`). Route 1 = upgrade that to a **visible** shard-case
  prop at the coord; walking up shows the note.
- **"Place shard X at Y" = one row in a Lua registry table** (`{id, pos={x,y,z}, title, lines}`). Claude owns
  it end to end — no new file types, no external tools.
- **Capture loop** (closest to the dream): reuse the mod's existing position capture — stand at the spot
  in-game → hotkey → coord written to the shard registry → prop spawns there on every load.
- **Persistence** across save/load = the same respawn-on-load machinery Jackie already uses.
- **Tradeoff:** it's a runtime-spawned marker, not a baked Codex shard / inventory item. For "walk up to a
  fixed spot and read Jackie's note" that's the right tool. If a proper Codex entry is ever wanted → Route 2.
- **Open detail:** interaction style — MVP = proximity auto-shows the note (like today's postShards, but with
  a visible object). A real "[E] Read" prompt needs an interaction component (Codeware) — nice-to-have later.

## Route 2 — "real" baked shard (TweakXL + ArchiveXL + World Builder)  ← for a proper Codex shard later
- Item/action/localization → Claude authors as text (above).
- `.journal` → make ONE in WolvenKit, clone per shard by swapping the LocKey (small, templatable).
- **Placement → World Builder** (Nexus 20660, a CET in-game tool): fly to the spot, drop the
  `shard_case_container.ent` visually (no hand-typing coords), export `projectName_exported.json` → a
  WolvenKit **import script** converts it to `.streamingsector` + `.streamingblock` for native world edits.
- So even the "native" route places visually in-game; the only manual-WolvenKit steps are the one-time
  `.journal` + the one-click sector bake. More moving parts than Route 1; not needed for MVP.

## Did ArchiveXL get undersold? Partly yes.
ArchiveXL **can** add world objects via **text** `.streamingsector`/`.xl` files, **non-destructively** (it
tells the game to load custom sectors merged into `all.streamingblock`). That's real, not a hack. What it
does NOT provide is authoring those sector nodes from a bare coordinate string — the practical workflow uses
World Builder for placement. So "type a coord, zero WolvenKit" is **not** the baked route, but it **is**
exactly Route 1 (CET spawn).

## The "mini-WolvenKit that edits the archive" idea — still don't build it
Programmatically opening/rewriting the `.archive` (custom RED-engine CR2W binary) = reimplementing
WolvenKit's serializer. Route 1 sidesteps the need entirely. Not worth it.

## Tracker tool (independent of route, EASY, do anytime)
`tools/shard-tracker/` + `shards.json`: id, world coords, "displays correctly?" status, last-updated stamp,
and the shard text (single source of truth). For Route 1 this file **is** what the mod reads to spawn shards.
Can be a Mac-side CLI/HTML tool or a CET panel.

## Recommended plan
1. Build the **tracker/registry** (`shards.json` + tool). Low risk, immediately useful.
2. **Route 1 MVP:** spawn a visible shard prop from a registry row at a coord; proximity shows the note;
   migrate the current `postShards` (Misty/Mama) onto it. Add the in-game capture hotkey.
3. Only if a proper Codex shard is later wanted: Route 2.
- **200-local cap:** globals or a `shards.lua` module, never new top-level `local`s in init.lua.

---

# ✅ DECISION (Antonia 2026-07-06): Route 2 — the real baked shard
Antonia chose Route 2 (a proper, readable, pick-up-able shard), with a strict split: **Claude authors
everything that is text; Antonia does ONE action in WolvenKit.** Below is (A) exactly what Claude does,
and (B) the beginner step-by-step for the single WolvenKit action.

## A) What Claude does — everything except the one WolvenKit action
All of this is plain text Claude writes into the repo; none of it needs WolvenKit:
1. **Item record** — a TweakXL YAML entry (`gamedataItem_Record`, `itemType: ItemType.Gen_Readable`), one
   per shard (e.g. `Items.jl_shard_jackie_01`). Claude writes it.
2. **Action record** — the TweakXL `gamedataItemAction_Record` whose `journalEntry:` points at the onscreen
   entry the shard shows. Claude writes it.
3. **Localization JSON** — the `localizationPersistenceOnScreenEntry` file holding the shard's **actual text**
   (title + body, femaleVariant). This is where Jackie's note lives; Claude authors + updates it. Editing a
   shard's wording later = Claude edits this JSON, **no WolvenKit needed**.
4. **The `.xl` + `.streamingsector` placement files** (ArchiveXL, text) that tell the game to load the shard
   container at the world coordinate. Claude writes these once we have the coords (see the coord-capture note).
5. **The tracker** (`tools/shard-tracker/` + `shards.json`) — single source of truth for id / coords /
   text / "displays correctly?" / last-updated. Claude builds + maintains it.
6. **A filled-in template of the `.journal` onscreen entry as text** — Claude writes down the exact id, title
   LocKey, description LocKey and `tag: articles` values so Antonia only has to type them into WolvenKit.

**The ONLY thing that is not text = the binary `.journal` "onscreen" resource.** That is the single
WolvenKit action below. It is a **one-time** action: after the first shard exists, every additional shard
is cloned from it by swapping two LocKeys (Claude supplies the new values; ~30 seconds each).

## B) The one WolvenKit action — beginner step-by-step (make the `.journal` onscreen resource)
> You only do this the first time (and a 30-second clone per extra shard). Claude gives you the exact
> values to paste; you never invent anything. If any label differs slightly by WolvenKit version, the
> shape (a JournalOnscreen resource with one Onscreen entry) is what matters — tell Claude what you see.

**Before you start:** open your JackieLives mod project in WolvenKit (the same project you deploy from).
Claude will hand you a small "shard sheet" with 4 values: **RESOURCE PATH**, **ENTRY ID**, **TITLE
LocKey**, **DESCRIPTION LocKey**.

1. **New file → JournalOnscreen resource.** In WolvenKit's Project Explorer, right-click the folder where
   you want it (e.g. `base\journal\`) → **Add New File…** → search the file-type list for **`journal`** /
   **`gameJournalResource`** (a "Journal" resource). Name it exactly the **RESOURCE PATH** filename Claude
   gives you (e.g. `jl_shard_jackie_01.journal`). Click Create — it opens in the editor.
2. **Open the tree** in the center editor. You'll see a root `gameJournalResource` with an `entries` array.
   You want to add ONE **`gameJournalOnscreen`** entry under it (the "onscreen" type is the readable-shard
   kind). Right-click the `entries` array → **Add Item** → pick **`gameJournalOnscreen`** from the type list.
3. **Fill the 4 fields** on that new entry from Claude's shard sheet (click each field, paste the value):
   - **`id`** → the **ENTRY ID** (a text string, e.g. `jl_shard_jackie_01`).
   - **`title`** → set its LocKey to the **TITLE LocKey** value.
   - **`description`** → set its LocKey to the **DESCRIPTION LocKey** value.
   - **`tag`** → type **`articles`** (this makes it render as a readable shard/article).
4. **Save** (Ctrl+S). The tab stops showing the "unsaved" dot.
5. **Install/pack the project** the normal way you deploy (WolvenKit **Install to game** / pack to your
   `mods` archive) so the `.journal` ends up in the game. Claude's TweakXL/ArchiveXL text files reference
   this exact path, so the shard item + the world placement + this onscreen entry all line up.
6. **In-game check:** walk to the shard's coordinate, pick it up / read it. If the title + body text show,
   it works. If it's blank or shows a raw `LocKey#…`, the LocKey values didn't match — send Claude a
   screenshot; the localization JSON (Claude's file) or the two LocKeys are the only things that can be off.
7. **To ADD another shard later:** in WolvenKit, right-click your working `.journal` → duplicate it (or add
   another `gameJournalOnscreen` entry), and change only the **id / title LocKey / description LocKey** to
   the new values Claude gives you. Save + install. Everything else (item record, text, placement) Claude
   handles in the repo.

**Coord capture (so Claude can write the placement file):** stand where you want the shard in-game and use
the mod's existing position-capture (the same hotkey used for seats/venues) — send Claude the printed
`x,y,z` (+ yaw). Claude bakes it into the `.streamingsector`. You do **not** hand-place anything in
WolvenKit; the only WolvenKit action is the `.journal` above.

## Why this split is safe
- The **fragile/binary** part (`.journal`) is tiny, done once, and templated — low chance of Antonia error.
- The **frequently-changing** parts (shard wording, which coords, which shards exist) are all **text Claude
  owns**, so day-to-day iteration never reopens WolvenKit.
- If even the one `.journal` action proves annoying, **Route 1 (CET runtime spawn) remains the zero-WolvenKit
  fallback** — but it produces a runtime marker, not a true Codex/inventory shard. Route 2 is the "real" one.

## Sources
- redmodding wiki — *Creating custom shards*
- redmodding wiki — *Adding Locations and Structures with ArchiveXL*; *Exporting from Object Spawner*
- World Builder — nexusmods.com/cyberpunk2077/mods/20660
