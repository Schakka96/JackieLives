# q005 heist music — where it actually comes from, and the WolvenKit options

_Written 2026-07-09. Analysis of the existing `docs/research/q005_raw/` export (58 `.quest` /
`.questphase` JSON files, the full q005 tree). Supersedes the guesswork in
`cet_scene_music_teardown.md` about **what owns** the bed._

## The headline finding (new, and it rules a whole approach out)

**The q005 quest graph does not play the heist music. There is nothing there to edit.**

I walked every node of all 58 exported files. The entire q005 tree contains exactly **two** audio
nodes (`questAudioNodeDefinition` → `questAudioEventNodeType`):

| Phase file | Event | `isMusic` |
|---|---|---|
| `q005_03_outside.questphase` | `mus_radio_09_downtempo_simple_pleasures` | 1 |
| `q005_09_no_tell_motel.questphase` | `q005_sc_14_delamain_driving_off` | 1 |

Neither is the escape score. Two further negatives, both checked:

- The 108 `questEventManagerNodeDefinition` nodes send **zero** audio events (they're
  `ToggleFocusClueEvent`, security-system, TV-channel, vehicle-light events — nothing audio).
- `q005_custom_music`, which looks promising on a grep, is a `questTogglePrefabVariant_NodeType`
  toggling the prefab `#loc_q103_afterlife_audio` in `q005_01_plan` / `q005_02_cab_ride`. It's the
  **Afterlife jukebox**, not the heist bed. Red herring.

So "open the questphase in WolvenKit and delete/bypass the music node" — the obvious first idea —
**is not available.** No such node exists.

### Which means the bed lives in a `.scene`, and that explains the logger silence

This closes the loop on the mystery from `cet_scene_music_teardown.md`. The CET
`ObserveAfter("gameGameAudioSystem", "Play"/...)` logger caught the pocket radio and UI jingles but
never the score. That's exactly what you'd expect if the music is a **scene-timeline audio event**:
the scene player posts those to Wwise natively in C++, without going through the scripted
`gameGameAudioSystem::Play` wrapper the logger hooks. Script-routed audio is visible; scene-routed
audio is not. The bed being invisible to the logger is *evidence for* the scene, not a dead end.

One correction to the old note while we're here: "un-muting brings the bed back" does **not** prove
the scene is still holding the music open. It only proves the Wwise event is still playing — a
looping music event that was never sent its stop keeps running behind a zeroed volume bus. Same
practical outcome, but the distinction matters for picking a fix.

### The scene shortlist

From the 100 `questSceneNodeDefinition` nodes, these are the scenes live during the escape — the
suspects for both the "goes wrong" music start and the scene that's still running at the Blaze finale:

```
base\quest\main_quests\prologue\q005\scenes\q005_09_attack.scene           <- Yorinobu kills Saburo; prime suspect for the music START
base\quest\main_quests\prologue\q005\scenes\q005_10_taking_the_chip.scene  <- prime suspect for the scene still RUNNING at the finale
base\quest\main_quests\prologue\q005\scenes\q005_12_escape_techie.scene
base\quest\main_quests\prologue\q005\scenes\q005_13_escape_netrunner.scene
base\quest\main_quests\prologue\q005\scenes\q005_14_after_escape.scene
```

---

## The thing that decides everything: archive edits are unconditional

This is the trade-off to internalise before picking a path.

Anything you ship in a WolvenKit `.archive` is **always on, for every playthrough**. If you strip the
music event out of `q005_09_attack.scene`, then a user who installs JackieLives and plays the *normal*
heist loses the iconic score too. There is no way to make a packed scene edit fire only during Blaze.

Runtime (CET) fixes are the only **conditional** ones. That's why the current `blazeMuteMusic()` —
crude as it is — has a real advantage the elegant WolvenKit fix doesn't.

So the best answer isn't "WolvenKit instead of CET". It's **WolvenKit as a lookup tool, CET as the
actuator.**

---

## The four paths you asked about, ranked

### ⭐ Path A — Use WolvenKit to *find* the event name, stop it from CET (recommended)

You already tried `blazeStopMusicEvent("<name>")` and couldn't get a name, because the logger can't
see native audio. But **you don't need the logger — the name is sitting in the scene file**, readable
statically. WolvenKit gives you the name; CET does the stopping. Nothing gets packed, nothing is
unconditional, zero compatibility surface.

Concretely, and this reuses the exact pipeline you already ran for the quest graph
(`q005_graph_extract.md`):

1. WolvenKit → Asset Browser → search `q005_09_attack` → right-click → **Add to project**. Repeat for
   the other four scenes in the shortlist above. (This time you *do* want `.scene` files — the
   opposite of last time's instruction.)
2. Right-click each in Project Explorer → **Convert to JSON**.
3. Drop them in `docs/research/q005_raw_scenes/` and push. I'll grep them for the audio events —
   they'll be `scnAudioEvent`-ish nodes on the section event tracks carrying a CName that almost
   certainly starts `mus_` or `q005_sc_`.
4. I wire `AudioSystem:Stop("<that name>")` into the finale, replacing the global mute.

**Cost:** ~20 min of your time, all on Windows, no gameplay. **Risk:** none — nothing ships.

**The honest caveat:** `Stop()` on a music event fired natively may not take (Wwise music often wants
a paired stop event rather than a Stop call on the play event). Roughly 60/40 in favour of it working.
If it doesn't, the same export tells us the event name *and* which scene owns it — which is exactly
what Path B needs. **Either way this export is the right next move, because both paths need it.**

### Path B — Delete the music event from the scene, ship the `.scene` (the real "never start that music")

This is the literal answer to "never start that music," and it *is* simple — much simpler than the
scene surgery in `wolvenkit_scene_editing.md`, because you're deleting an **event on a track**, not a
node in the graph. The scene's structure and flow are untouched, so the soft-lock risk that doc warns
about ("never leave a node with no exit path") doesn't apply here. Open the scene in the Scene Editor,
find the audio event on the section's event track, delete it, pack.

**Cost:** small, once you know which event. **Risks:**
- Unconditional (see above) — kills the score in vanilla q005 for anyone with the mod installed.
- Overrides a base-game main-quest scene → hard conflict with any other mod touching q005.
- Only kills the music if the bed really is a scene event. If it turns out to be the **dynamic combat
  mix** rather than a scene event, there's nothing in the scene to delete and the mute is the only fix.
  The Path-A export resolves this ambiguity for free.

### Path C — "End the scene" from WolvenKit

**Not achievable, and WolvenKit is the wrong tool by construction.** A `.scene` ends when the quest
graph that owns it advances past its `questSceneNodeDefinition`. WolvenKit edits *static data*; it has
no way to reach into a running scene. You already verified the other half of this from the script side:
the whole `SceneSystemInterface` exposes only fast-forward / rewind / camera / read-only queries — no
Stop, Kill, or Cancel. There is no scripted abort and no static abort. This path is closed from both
ends; don't spend more time on it.

### Path D — Drop the heist from V's job list / kill the scene tree

Two separate things, and neither does what you want.

**Dropping it from the job list is cosmetic.** The journal entries are a parallel presentation layer.
I pulled the exact tree — the quest is `gameJournalQuest` at `quests/main_quest/prologue/q005_heist`,
with ~60 `gameJournalQuestObjective` children under `the_plan/`, `cab_ride/`, `arasaka_undercover/`,
`arasaka_escape/`, `return/`. Removing them hides the text in the journal. **The quest phases and
scenes still run exactly as before, so the music still plays.** You'd have solved nothing and lost the
HUD tracker.

**Killing the scene tree is self-defeating.** Two reasons, either one fatal:
1. q005 *is* the prologue. Blank its phases and V never gets the biochip, never leaves Konpeki, and
   there is no game to mod.
2. Blaze runs **inside the live q005**. It's a what-if hosted by the very quest you'd be deleting.
   Killing q005 kills Blaze's own host. You'd have to re-home the whole set-piece in a custom quest
   first — which is a ground-up rewrite, not a music fix.

This is the one you flagged as "probably hardest," and that instinct was right — but it's worse than
hard, it's backwards. Note it as closed.

---

## Recommendation

Do the **Path-A export** (the five `.scene` files → JSON → push). It is 20 minutes, ships nothing, and
it is a strict prerequisite for *both* live options — it either hands us a name to `Stop()` (Path A,
conditional, clean) or tells us the event to delete (Path B) or proves it's the combat mix (in which
case `blazeMuteMusic` stays and we stop looking).

Keep `blazeMuteMusic(true)` wired in as the default in the meantime. It's ugly, it's global, and it
works.

## Status
- [x] Quest graph ruled out as the music source (this doc, from `q005_raw/`).
- [x] Scene shortlist derived; journal tree mapped.
- [ ] **NEXT — Antonia:** export the 5 escape `.scene` files to JSON → `docs/research/q005_raw_scenes/`.
- [ ] Claude: grep for the audio event CName → wire `AudioSystem:Stop()` or spec the scene edit.
