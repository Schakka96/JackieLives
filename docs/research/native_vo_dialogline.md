# Playing the game's OWN voice lines at runtime — `DialogLineEvent`

**Status: technique found, not yet tested. This REVERSES the "no runtime VO by String ID" verdict**
recorded in `TODO.md` (~lines 3073, 4223, 4412–4455) and in Claude's memory. That verdict was wrong.

**Source:** *V Voice Framework* (Nexus 30646, v1.32) —
`reference_mods/V Voice Framework 30646 1.32 .../r6/scripts/Johnny Voice Framework.reds`.
See `../../../GROUND_RULES.md` for what `reference_mods/` is and why it is never published.

---

## What we believed, and why it was wrong

The old research concluded that CP2077 exposes no way to say *"play line #1660220866564214792 now"* —
only `PlayVoiceOver(npc, context)`, where the game picks the line. Everything tried was in the
**audio** layer: `AudioEvent`, `SoundPlayEvent`, `AudioSystem:Play` (WWise event names only),
`scnVoicesetComponent`. All dead ends, correctly.

The door is in the **dialogue** layer, not the audio layer. The game already plays an arbitrary
chosen line every time an NPC speaks in a scene; the event that carries it is `DialogLineEvent`, and
nothing stops a mod from queueing one itself. It was missed because `DialogLineEvent`,
`audioDialogLineEventData`, `entInjectVoiceTagEvent` and `HashToCRUID` are **native-only** — they do
not appear anywhere in the decompiled script dump (verified: zero hits across
`CDPR-Modding-Documentation/Cyberpunk-Scripts`), so grepping the dump could never have found them.
They exist only in the RTTI, which redscript can see.

## The technique

`Johnny Voice Framework.reds:109–133`, condensed:

```swift
// 1. Point the audio system at whose voice bank to draw from.
let inj = new entInjectVoiceTagEvent();
inj.voiceTagName = n"johnny";
this.QueueEvent(inj);

// 2. Play one specific line, by its String ID.
let audioEvt = new DialogLineEvent();
let d: audioDialogLineEventData;
d.stringId = HashToCRUID(ruid);          // <- the whole trick
d.isPlayer = false;
d.context  = locVoiceoverContext.Vo_Context_Combat;
audioEvt.data = d;
this.QueueEvent(audioEvt);

// 3. Draw the subtitle ourselves, 0.1s later (audio has ~1 frame of startup latency).
//    scnDialogLineData{ id = HashToCRUID(ruid), type = OwnerlessRegular, text, speakerName, duration }
//    pushed onto UIGameData.ShowDialogLine — the path JackieLives already uses.
// 4. HideDialogLine at dur + 0.4, and restore the voice tag to n"v".
```

Three things worth naming:

- **`entInjectVoiceTagEvent`** exists because JVF plays *Johnny's* lines out of *V's body*. It
  temporarily rebinds which voice bank that entity speaks from, then restores `n"v"`. **We may not
  need it at all** — our speaker is a real Jackie entity who presumably already carries the `jackie`
  voice tag. Open question 3 below.
- **Duration is supplied by the caller**, not discovered. JVF hardcodes a `dur` per line, extracted
  from `vset_johnny.scene`. So we must ship a duration table.
- **`Vo_Context_Combat`** is a `locVoiceoverContext` enum value. Presumably it selects the audio
  processing/mix bus rather than the line; other values are worth trying if the mix sounds wrong.

## What this buys us, concretely

| | today (Audioware) | with `DialogLineEvent` |
|---|---|---|
| Audio shipped | none — the player extracts ~940 MB themselves | none, and nothing to extract |
| Player setup | install Audioware + WolvenKit, extract VO, rebuild the bank manifest | **nothing** |
| Dependencies | Audioware (hard, for voice) | none new *if* it works from Lua (see below) |
| Failure mode | one missing `.wav` → Audioware drops the entire bank → total silence | a bad ID → that one line is silent |
| Quality | re-encoded Vorbis, or WolvenKit-extracted WAV | the game's own audio, untouched |
| Copyright | fine but fragile — we're one careless zip from shipping CDPR audio | nothing to ship, so nothing to get wrong |
| Lipsync | none — hence the "talking-face flap" hack | **possibly free** (open question 4) |

It also **obsoletes the audio provisioner** (`GROUND_RULES.md` rule 3b) before it was ever built.
The provisioner was the answer to "how do we stop making users extract audio by hand"; the correct
answer turns out to be "don't need the audio files".

**Our String IDs are already the right numbers.** `audioware/JackieLives/index.json` keys are decimal
String IDs in the range 1.6e18–2.25e18; JVF's RUIDs are 2.25e18. Same namespace — the trailing hex
token of a `.wem` stem, in decimal, which is exactly what `rebuild_bank_yml.py` documents. All 777
catalogued lines (and the 1280 in `lines.json`) drop straight in with no re-cataloguing.

## The one real risk: JackieLives is pure CET Lua, JVF is redscript

The mod ships no redscript today (`TODO.md:3010` — "NOT needed: Audioware, redscript, TweakXL,
ArchiveXL"). Three sub-questions, in the order they should be answered:

1. Can CET Lua construct `DialogLineEvent` and set a **nested struct field** (`audioEvt.data` is an
   `audioDialogLineEventData`)? This is the part most likely to fail — CET handles flat native
   objects well and nested structs unevenly.
2. Is `HashToCRUID` reachable from Lua, or does a `CRUID` have to be built another way?
3. ⚠️ Per `cet-rtti-types-need-bare-globals`: construct with a **bare global**
   (`DialogLineEvent.new()` / `NewObject("DialogLineEvent")`), never `_G["DialogLineEvent"]`.

If Lua can't do it, the fallback is JVF's own shape: a ~40-line `.reds` file exposing one method that
Lua calls. That adds **redscript** as a dependency — a new *class* of dependency (`DEPENDENCIES.md`
question 3), which is a real cost. But it replaces Audioware **plus** a 940 MB manual extraction, so
it is still a large net win, and redscript is a far more common install than Audioware.

## Open questions — answer these before writing engine code

1. **Lua reachability** (above). Answer with a CET-console spike, not by reading.
2. **Does it work on an NPC?** JVF only ever queues on `PlayerPuppet`. We need it on Jackie's spawned
   entity. Nothing in the event's shape suggests it's player-only, but it is untested.
3. **Is the voice-tag injection needed for a real Jackie?** Try without it first. If his lines come
   out in the wrong voice (or silent), inject `n"jackie"` and restore afterwards — and find the
   correct tag name, don't assume it's `"jackie"`.
4. **Lipsync.** This is the game's real dialogue path, so it plausibly drives visemes natively — which
   would retire the `talking-face flap` hack and the AMM Expressions Overhaul suggestion. High value
   if true; verify by watching his mouth, not by reasoning.
5. **Durations.** Compute once, on the Mac, from the SoundDB `.ogg` files we already scrape
   (`ffprobe`), and commit a small `id → seconds` table. Text-length estimation is the fallback we
   already have.
6. **Male/female V variants.** Jackie's stems carry `_f_` / `_m_` infixes (e.g.
   `jackie_q000_f_170a4a14f8405008`). Those are separate String IDs, so V's body gender may need to
   pick between two IDs for the same written line. Check before assuming one ID fits both.
7. **Cooldown.** JVF gates every line behind one global cooldown so that stacked mods don't talk over
   each other. Ours is a conversation system, not a reaction system — we must NOT adopt a 10s gate,
   but we do need a "don't start line B while line A is playing" queue. We already have one.

## What the mod's `.archive` is (and why we don't need one)

`archive/pc/mod/V Voice Framework.archive` is **a single file**: one 10 MB `scnSceneResource`
(verified with `redlib.py`; the CR2W string table is full of voiceset names — `battlecry_curse`,
`scene_thanks`, `gp_vehicle_steal`…). It is a replaced **vset scene**, and it belongs to the mod's
*other*, unrelated half: `VFV_PlayVoice(voiceName)` (`V Voice Framework.reds:135`), which plays a
**named voiceset** on V through `questPlayVoiceset_NodeType` + `QuestsSystem.ExecuteNode`. That is a
different mechanism with a different purpose (V reacting to gameplay), and it *does* need an archive
because they added voiceset entries.

**The RUID technique needs no archive at all.** They extracted Johnny's RUIDs from `vset_johnny.scene`
read-only, at authoring time. So: ignore the archive, ignore `VFV_PlayVoice`, port `JVF_PlayLine`.

## Suggested order of work

1. **CET-console spike on Windows** — one line, on Jackie, no subtitle. Question 1, 2, 3 at once.
   This is ~20 lines and settles whether the whole route is Lua-only or needs redscript.
2. If it plays: duration table from the scraped `.ogg`, then wire `speakJackieLine` to prefer the
   native path and keep Audioware as a fallback for anyone who already built a bank.
3. Watch his mouth (question 4). If visemes come free, retire the flap.
4. Then, and only then, decide whether Audioware/`rebuild_bank_yml.py`/`convert_audio.py` get deleted
   or kept as a legacy path. Git history is the archive — lean toward deleting.
