# Dialogue editor

A little local web app to **read, browse and edit every line Jackie (and V, and Vik,
and Misty, and Mama Welles) says** — without hand-editing Lua.

It reads the dialogue straight out of `mod/JackieLives/config.lua` and
`mod/JackieLives/retrieval.lua`, shows each conversation as a **tree you can pan and
zoom**, and writes your edits **back into those same .lua files** — leaving every
comment in them exactly where it was.

Nothing is downloaded, nothing is installed, and it works offline. It's just Python's
built-in web server plus one HTML page.

---

## Run it

You need **Python 3** (any version from 3.7 up). That's it — no `pip install`, no npm.

### On the Mac

1. Open **Terminal**.
2. Type this and press Enter:

   ```
   cd ~/Documents/Private_Projects/Mods/JackieLives
   python3 tools/dialogue-editor/serve.py
   ```

3. It prints something like:

   ```
   JackieLives dialogue editor
     mod dir : /Users/antonia/.../mod/JackieLives
     parsed  : 26 sections, 69 tree nodes, 320 editable lines
     verifier: luac

     ==> open  http://localhost:8777
   ```

4. Open **http://localhost:8777** in your browser.
5. When you're done, click back on the Terminal window and press **Ctrl+C** to stop it.

### On Windows

1. If you don't have Python yet: install it from https://www.python.org/downloads/
   — and on the first screen **tick "Add python.exe to PATH"** before clicking Install.
2. Open **PowerShell** (Start menu → type "powershell" → Enter).
3. Type this and press Enter (adjust the path if your repo lives somewhere else):

   ```
   cd C:\Users\<you>\Documents\JackieLives
   python tools\dialogue-editor\serve.py
   ```

   (On Windows the command is `python`, not `python3`.)

4. Open **http://localhost:8777** in your browser.
5. Press **Ctrl+C** in PowerShell when you're done.

> If PowerShell says `python is not recognized`, Python isn't on your PATH — reinstall
> it and make sure that tick-box in step 1 is ticked.

---

## Using it

**Left sidebar** — every conversation, grouped by who's talking and what the situation is
(Jackie → Reunion call, Jackie → At Misty's Esoterica, Vik → Retrieval tip, Notes/Shards…).
The little box at the top filters the list.

**Middle** — the conversation.

* **Branching trees** are drawn as a graph: it flows **left → right**, and where a choice
  branches, the branches spread **downward**.
  * **Drag** the background to pan. **Scroll wheel** to zoom. **Fit** re-centres everything.
  * The node ringed in **cyan** is where the conversation *starts*.
  * A node tagged **end** is a dead end — the conversation stops there.
  * The cyan lines are the actual connections: a choice (`▸ …`) links to the node its
    `to` points at. Click the little **→ nodename** label on a choice to jump to it.
  * **Click any line** to open the editor panel on the right.
* **Flat line pools** (arrival greetings, farewells, the shards…) are a simple list you
  type straight into. Where there are two versions of a pool they're shown side by side.

### Changing the shape of a conversation

You can restructure a tree, not just retype it:

* **`+ Add node`** (top bar) — a new thing for Jackie to say. You **must** say which
  existing node leads to it, in the same box: a node nothing points at can never be
  reached in-game, so the tool won't make one. You can optionally give it a reply that
  leads back out.
* **`delete node`** (on the node) — **refused** while any reply still points at it, and it
  names the exact replies so you can repoint or delete them first. The `start` node can't
  be deleted at all.
* **`+ reply`** (on the node) — a new reply option for V. Pick where it leads, or end the
  conversation there.
* **`×`** (on a reply) — delete that reply. Always allowed. If that leaves a node with
  nothing pointing at it, you get a **warning** naming the stranded node — it's not
  blocked, because sometimes that's exactly what you're mid-way through doing.
* **Voice clip** (right panel) — type an id, or hit **Pick…** to search Jackie's ~1,200
  real recorded lines *by what he actually says*. Empty = text-only.
* **Where this reply leads** (right panel) — repoint a reply at a different node.

Structural changes save **immediately** (along with any text edits you had pending), so
what's on screen is always what's in `config.lua`.

**Right panel** — the editor for whichever line you clicked. Every line can have two texts:

| | |
|---|---|
| **Husbando** | the base `text` — what Jackie says to a **female V** |
| **Hermano** | the `m = { text = ... }` variant — what he says to a **male V** |

If a line has no Hermano variant, it means it's content-neutral and gets reused as-is for
both. (Adding a *new* `m` variant is still a by-hand Lua edit — this tool only edits text
that's already there.)

The panel also shows, **read-only**:

* the **voice clip**, and **what the clip actually says**. If the subtitle has drifted away
  from the recording, the box turns amber and tells you so. (That mismatch is exactly what
  the v1.56 rewrite was cleaning up — subtitles that had been bent to fit whatever clip was
  to hand.) A line with **no** clip is text-only; in a `muteFallback` tree that means
  genuinely **silent**, so you can reword it freely.
* badges like `chance`, `once`, `final`, `textPool` — behaviour, not words, so not editable.
* `cond` — a real Lua **function** that decides whether a reply shows at all. It's code, so
  it's shown read-only and its bytes are never touched.

**Saving** — edited lines get an orange bar. The header shows how many are unsaved.
Hit **Save all**. A green banner means it's written; a red banner means it was refused
and *nothing* was changed.

---

## Why you can trust it with config.lua

`config.lua` is full of comments, and in this project those comments are the
documentation. A tool that re-wrote the Lua from scratch would wipe them all out. This one
doesn't do that. It does something much narrower:

* When it reads a file, it records the **exact character positions** of each piece of text
  inside the quotes.
* When you save, it swaps **just those positions** for your new text (properly escaped),
  back-to-front so the earlier positions stay valid. Every comment, every blank line,
  every setting it doesn't understand is left byte-for-byte alone.

And before it lets a save stand, it runs **two** gates — and it does both *before* it writes
anything, so a rejected save leaves your files completely untouched:

1. **Is it still valid Lua?** — via `luac`/`lua` if you have them, otherwise a built-in
   structural check. You don't need Lua installed; it's a belt on top of the braces.

2. **Is it still a valid _dialogue_?** — this one matters more, and it's why structural
   editing is safe. `luac` will happily bless a file where a reply points at a node you
   just deleted: perfectly valid Lua, and a conversation that **dead-ends in-game**. So the
   tool also walks every tree and checks that

   * the `start` node exists,
   * every reply's `to` names a node that's really there,
   * nothing has been left stranded (a node nothing leads to → *warning*, not a block).

   A dangling `to` is a hard **error**: nothing is written, and the message names the exact
   node and reply.

3. Only once both pass does it **back the file up** to
   `tools/dialogue-editor/backups/config.lua.bak-<timestamp>` and write. It then re-checks
   what actually landed on disk, and restores the backup if anything is off.

4. If the file changed on disk since the page loaded it (say you edited it in your code
   editor too), the save is **refused** and it tells you to reload — so you can't clobber
   your own work.

*Lua-valid is not the same as dialogue-valid. A broken `config.lua` stops the mod loading
at all; a dangling `to` silently breaks the quest. Both are blocked.*

### Backups

They pile up in `tools/dialogue-editor/backups/`. Delete them whenever you like — that
folder is deliberately *outside* `mod/JackieLives/`, so `deploy.ps1` never copies
backup files into the game.

---

## Options

```
python3 tools/dialogue-editor/serve.py --port 9000     # use a different port
python3 tools/dialogue-editor/serve.py --check         # just parse + report, don't serve
python3 tools/dialogue-editor/serve.py --mod-dir <dir> # point at a COPY of the .lua files
```

`--mod-dir` is the safe way to try something out: copy `config.lua` and `retrieval.lua`
into a scratch folder, point the tool at it, and the real mod is never touched.

---

## After you edit: get it into the game

`mod/JackieLives/` is the source of truth — that's what this tool edits. The packaged copy
in `staging/` does **not** update itself. So once you're happy:

* to test in-game on Windows: run **`deploy.ps1`**;
* to refresh the Nexus zip layout: run **`tools/package_nexus.sh`**.

If you skip that, you'll be testing the old lines and wondering why nothing changed.

---

## What it does *not* do

Honest limits, so nothing surprises you:

* It edits **trees** structurally (nodes, replies, `to`, `sfx`). It does **not** add or
  remove entries in the flat **pools** (arrival greetings, farewells, shard paragraphs) —
  those are still text-only here; add a line by hand in the `.lua` and it appears on reload.
* It doesn't edit `chance`, `once`, `final`, `action`, `fact` or `cond` — those are wiring
  and logic, not words. They're shown, never touched.
* Adding a **new** `m` (Hermano) variant to an existing line is still a hand-edit; the tool
  edits the ones already there. (New nodes/replies you create here *can* have one.)
* Long strings written as `"a" .. "b" .. "c"` across several lines (Vik's tip, the shard
  paragraphs) get rewritten as **one long line** when saved. Same text, still valid Lua,
  just a wider line in the file.
* Deleting a node leaves any **comment block above it** behind — deliberately. The tool
  will never delete a comment you didn't ask it to; tidy it by hand if you want it gone.
* `blaze.lua` and `init.lua` aren't read — there's no dialogue data in them.
