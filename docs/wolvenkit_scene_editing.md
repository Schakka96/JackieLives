# WolvenKit scene editing — how dialogue actually works (reference)

_Written 2026-07-08 while learning to edit `.scene` files for mourning removal. Keep for later._

## The one concept that explains everything
A `.scene` file stores **structure and a *pointer* to text — never the text itself.**
1. **Structure** (visible in the Scene Editor graph): which actor speaks, when, animations
   (`idle_joy_female`), `lookAt`, timing, branching.
2. **A pointer to the words:** each line holds a `locstringId → ruid` (a long number). The actual
   sentence lives in a **separate localization string table**, keyed by that ruid.

So the editor shows *how* the conversation flows; the *words* live elsewhere. This is why you can open
a scene and see nodes but no readable dialogue.

## Anatomy of a spoken line
- `root.screenplayStore.lines[]` = the master list of **every line in the scene**, in order.
- Each entry (e.g. `lines[2]`, id **513**) has:
  - `locstringId.ruid` — the pointer to the text (the long number).
  - `femaleLipsyncAnimationName` / `maleLipsyncAnimationName` — the mouth animation for that line.
- In the graph, a line is played by a **`scnDialogLineEvent`** sitting inside a **Section node**, on the
  section's **dialogue/audio event track** (a *different* track from the animation events like `idle_joy`
  and `lookAt` — those are body/camera, not speech).

## Why WolvenKit shows a number instead of words
WolvenKit only resolves ruid → sentence if your install has the localization **indexed**. If it isn't,
you see the raw ruid. Nothing is wrong — it's just unresolved. Fighting this is usually not worth it.

## The TWO localization tables (they are different!)
1. **`base\localization\en-us\onscreens\onscreens.json`** — UI + **phone SMS + journal + shards +
   choice labels + contact names**. Keyed by small `primaryKey` (≤5 digits). We have this extracted.
   Grep it with `tools/loc_grep.py`.
2. **Scene VO subtitles** (the spoken lines) — keyed by the 19-digit scene **ruid**. These are **NOT**
   in `onscreens` (confirmed: 0/2339 scene ruids resolve there, and no bit-transform matches). They live
   in the subtitles localization (`base\localization\en-us\subtitles\...`), which we have NOT extracted.
   → To resolve spoken lines to text, extract that subtitles table; then ruid → sentence is a lookup.

## How to READ the lines (practically)
- **Fastest:** an online transcript (Fandom wiki / YouTube) of the specific call, matched to the **order**
  of `screenplayStore.lines[]`. Good enough to know which line is which.
- **In-editor:** click a `scnDialogLineEvent` on the dialogue track; if loc resolves, the sentence shows
  as its label/tooltip. Often blank — see above.
- **Exact map:** extract the subtitles localization and have Claude resolve every ruid → text for the
  scene (ordered `line 513 = "…"` list).

## How to REMOVE / EDIT a line (you don't need the words to do it)
You edit by **structure/position**, not by text:
- **Delete one line:** select its `scnDialogLineEvent` in the section's event list → delete it (also its
  paired lipsync/anim/lookAt events for that line).
- **Skip a whole beat:** drag a connection from the node *feeding* the grief section to the node *after*
  it (bypass), then delete the orphaned section.
- **The one rule:** never leave a node with no exit path, or the conversation soft-locks. Every input
  must still reach an output. Test on a throwaway save after each change.
- Identify *which* line is the grief one by its **order + context** (e.g. it's in a `holo_misty_calls_v`
  = Misty-initiates section), and confirm against a transcript via the ruid.

## Applied to our mourning work
- Misty/Vik/Takemura/Mitch **spoken** grief = this scene-surgery route (their text isn't in `onscreens`).
- `misty_holocall.scene`: only 3 sections, branches on plumbing facts only (no Evelyn/tarot) — and we
  only suppress the **`holo_misty_calls_v`** (Misty-rings-V) direction, leaving **`holo_v_calls_misty`**
  (V rings Misty, used for Evelyn/tarot) intact. So the v1.31 fact-suppression is well-scoped.
- The **text** mourning (messages/journal) is in `onscreens` and is tiny (see `mourning_suppression.md`).
