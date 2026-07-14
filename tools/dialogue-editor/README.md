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

**Right panel** — the editor for whichever line you clicked. Every line can have two texts:

| | |
|---|---|
| **Husbando** | the base `text` — what Jackie says to a **female V** |
| **Hermano** | the `m = { text = ... }` variant — what he says to a **male V** |

If a line has no Hermano variant, it means it's content-neutral and gets reused as-is for
both. (Adding a *new* `m` variant is still a by-hand Lua edit — this tool only edits text
that's already there.)

The panel also shows, **read-only**:

* the **voice clip id** (`jl_…`). **If a line has one, it has real VO** — so the subtitle
  needs to keep matching what the clip actually says, or the audio and the words will
  disagree. Lines with *no* clip are silent, so you can reword them freely.
* badges like `chance`, `once`, `final`, `textPool` — those are behaviour, not words, and
  aren't editable here.

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

And before it lets a save stand:

1. It **backs the file up** to `tools/dialogue-editor/backups/config.lua.bak-<timestamp>`.
2. It **checks the result is still valid Lua** — with `luac`/`lua` if you have them
   installed, otherwise with a built-in structural check (both are run when available).
3. If that check fails it **puts the backup straight back** and shows you a red banner.
   *A broken config.lua means the mod won't load in-game, so it will never leave one on disk.*
4. If the file changed on disk since the page loaded it (say you edited it in your code
   editor too), the save is **refused** and it tells you to reload — so you can't
   clobber your own work.

You don't need Lua installed. It's just an extra belt on top of the braces.

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

## What it does *not* do

Honest limits, so nothing surprises you:

* **It edits existing text. It doesn't add or delete lines, nodes or choices.** Adding a
  new node, a new choice, or a new `m` variant is still a hand-edit in `config.lua`.
  (Once you've made it there by hand, it shows up here on the next reload.)
* It doesn't edit `sfx`/clip ids, `chance`, `to`, `action` or any of the numbers — those
  are wiring, and getting them wrong breaks the mod or the audio bank.
* Long strings written as `"a" .. "b" .. "c"` across several lines (Vik's tip, the shard
  paragraphs) get rewritten as **one long line** when saved. Same text, still valid Lua,
  just a wider line in the file.
* `blaze.lua` and `init.lua` aren't read — there's no dialogue data in them.
