# q005 quest-graph extract — the go/no-go for the "keep all 3" Blaze route

_Created 2026-07-06. Supersedes the JLFactDump fact-spike as the way we answer the ONE open
question. The spike proved fact-flipping can't help (see "Why" below); the quest graph answers it
directly._

## Why we're doing this (what the spike concluded)
The JLFactDump runs showed `q005_done` and `q101_started` are **both already `1` by the No-Tell
Motel** and move as one block tied to the Heist ending. There is **no fact seam** between "Watson
unlocks" and "Johnny/biochip starts" — matching the research warning that no standalone fact lifts
the lockdown. So we stop hunting facts and **read the actual quest graph**, which shows the nodes
and edges the facts only hint at.

## The one question this answers
> In the `q005` graph, is the **"Heist complete → Watson lockdown lifts → Act-2 world unlocks"**
> path **separable** from the **"install biochip → Jackie dies → start q101 (Johnny)"** branch —
> i.e. can we cut the death/q101 branch and still reach the world-unlock node?
>
> - **YES, separable** → the "keep all 3" route is feasible; I write the exact WolvenKit edit.
> - **NO, welded to one node** → we fall back (drop no-Johnny, or the sandbox route) — decided then.

## Your job (Windows, WolvenKit) — ~20 min, no gameplay
You're just **exporting files to JSON text and sending them to me.** I do the graph reading.

1. Open **WolvenKit** and your JackieLives project (same one as the voice bank).
2. Open the **Asset Browser** (the searchable game-archive file tree).
3. Run these three searches and, for every match with a **`.quest`** or **`.questphase`**
   extension, right-click → **Add to project** (extract it). Ignore `.scene`, `.anims`, textures,
   audio — we only want the quest-logic files.
   - search: **`q005`**   → the Heist quest + all its phases (the main target)
   - search: **`q101`**   → the Act-2 opener (so I can see what triggers it)
   - search: **`lockdown`** → _(optional)_ there is **no file literally named "lockdown"** (you'll only
     see `.bk2`/`.ent`/meshes — unrelated). That's expected: the lockdown is welded to the Heist, so its
     logic lives **inside the q005 phases above.** Skip this search — q005 covers it.
   > Tip: the file count should be modest — a handful of `.quest` and several `.questphase` each.
   > If a search returns hundreds of hits, you've got `.scene`/anim noise in there; filter to
   > `.quest`/`.questphase` only.
4. **Convert each extracted file to JSON.** ⚠️ **The "Export" button is greyed out for quest files —
   that's expected.** "Export" is only for raw art (textures→PNG, meshes→GLB, audio→WAV). Quest files
   use a different command: **right-click the file in the Project Explorer → "Convert to JSON"** (some
   builds: *Convert to → JSON*). It drops a `.json` next to the file in the project folder on disk,
   roughly `…\<Project>\source\archive\base\quest\…\*.json`. That `.json` is what you send.
   > If you don't see "Convert to JSON" in the right-click menu, **send me one screenshot of that
   > menu** — the wording moved between WolvenKit releases and I'll name the exact click. Don't fight
   > the tool.
5. **Send them to me.** Two easy ways, either is fine:
   - Drop all the `.json` files into `docs/research/questgraph/` in the repo and commit/push, **or**
   - Zip them and paste them into our chat.

## What I'll do with them (Mac, my job)
- Map the **end of `q005`**: find the phase node that completes the Heist, the node/event that lifts
  the Watson lockdown, and the node/event that installs the biochip + starts `q101`.
- Determine whether those sit on **separate edges** (cut-able) or the **same node** (welded).
- Return either: the **exact WolvenKit node edit** to reroute the end so the world unlocks without
  q101 — or an honest "not separable, here's the fallback."

## Status
- [ ] Antonia: export `q005` / `q101` / `lockdown` `.quest`+`.questphase` to JSON and send.
- [ ] Claude: read the graph → separability verdict + exact edit (or fallback).
- [x] JLFactDump fact-spike — **CONCLUDED**: no fact seam; superseded by this graph read.
