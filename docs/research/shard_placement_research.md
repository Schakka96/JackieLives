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

## Sources
- redmodding wiki — *Creating custom shards*
- redmodding wiki — *Adding Locations and Structures with ArchiveXL*; *Exporting from Object Spawner*
- World Builder — nexusmods.com/cyberpunk2077/mods/20660
