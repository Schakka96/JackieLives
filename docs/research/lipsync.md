# Lip movement / talk animation — feature writeup

How Jackie's mouth was made to move when he speaks. Self-contained record of the investigation,
what works, what's shipped, and what's left. (Built 2026-06-17.)

## The problem
Jackie's mouth was frozen while he "spoke." Real Cyberpunk lipsync is **JALI-baked** per line into
`.scene` resources; there is no public JALI tool. Our dialogue plays audio two ways — vanilla barks via
`AudioSystem:Play`, and the 777 scraped lines via **Audioware** — and **neither path carries facial data**,
so the engine's viseme system never animated his face.

## Investigation (CET reflection + live-component probe)
A probe (Codeware `Reflection` + a live dump of the spawned Jackie's components) established:
- **His face rig is fully intact** — components `face_rig`, `man_face_base_animations`,
  `entAnimationControllerComponent`, `scnVoicesetComponent`, plus jaw/teeth/head/eyes meshes. So the
  frozen mouth was a **driver** problem, not a missing part.
- `entAnimationControllerComponent` exposes `PushEvent`/`SetInputBool`/`ApplyFeature`; pushing guessed
  anim-event/input names did **nothing** (the flap isn't an anim event).
- `gameWorkspotGameSystem` is reachable (`PlayInDevice`/`PlayNpcInWorkspot`/`SendJumpToAnimEnt`).
- `scnVoicesetComponent` exposes almost nothing to CET (only `IsGenericTalkInteractionEnabled`).

Full probe output was written to `facial_methods.txt` in the CET mod folder (gitignored runtime artifact).

## Routes tried
- **Route A — push facial anim events from CET (`entAnimationControllerComponent`).** FAILED — the body
  anim controller doesn't drive the facial sub-rig from a guessed event/input name.
- **Route B — "abusing workspots" (invisible `.ent` + `.workspot`).** Confirmed *callable*
  (`gameWorkspotGameSystem`), but **abandoned**: couldn't extract a usable conversation-workspot path
  (a talking ambient NPC reports `IsActorInWorkspot=true` but 0 tags / no readable resource), and a body
  workspot wouldn't reliably carry a facial track. See `route_b_workspot_plan.md`.
- **Route C — `PlayVoiceOver` (THE answer).** The mouth flap is driven by **playing a voice-over**, whose
  audio auto-generates visemes through `scnVoicesetComponent`. This is exactly AMM's built-in "NPC Talk".

## What works (verified in-game)
**Real voice + real lipsync** via AMM's `Util:NPCTalk` recipe — CET, no WolvenKit:
```lua
local stim = npc:GetStimReactionComponent()
local anim = npc:GetAnimationControllerComponent()
stim:ActivateReactionLookAt(Game.GetPlayer(), false, 1, true, true)
Game["gameObject::PlayVoiceOver;GameObjectCNameCNameFloatEntityIDBool"](
  npc, CName.new(ctx), CName.new(""), 1, npc:GetEntityID(), true)
local f = NewObject("handle:AnimFeature_FacialReaction"); f.category = 3; f.idle = 5
anim:ApplyFeature(CName.new("FacialReaction"), f)
```
`ctx` is a voiceset **context token** (a *situation*, not a raw audio-event name). `"greeting"` is confirmed
working (mouth moves + a line plays). Raw WWise/scene event names (`ono_jackie_greet`, `vo_3d_jackie`) do
**not** work here — they aren't contexts.

## What's shipped
**Talking-face flap** wired into the dialogue runner (`JackieLives`, v0.34a). Because our Audioware lines
aren't VO events, they can't drive real visemes — so while a Jackie line plays we **shuffle facial
"Talking" anims** on his face for the line's duration:
- Faces come from **AMM Expressions Overhaul** "Talking" set: `AnimFeature_FacialReaction`,
  **category = 7, idle = 231..266 (242 skipped)**, 36 faces (read from
  `AppearanceMenuMod/Collabs/Extra_Expressions_AMM.lua`).
- Engine in `init.lua`: `flap`/`flapIdles`/`applyTalkingFace`/`startFlap`/`flapTick`. `startFlap(secs)` is
  called from `speakJackieLine` (branching) and `dialogueTick` (linear, Jackie lines only); `flapTick` (in
  `onUpdate`) shuffles a random face every **~0.9s** until the line elapses, then `ResetFacial`.
- No-ops gracefully if the Overhaul isn't installed; never touches V's lines; does nothing on holocalls
  (Jackie isn't in the world yet).

**Dependency added:** AMM Expressions Overhaul (Nexus mods/20108) — required for the flap faces.

## Test harness
Standalone CET mod **`mod/JackieLipsync/`** (window "Jackie Lipsync"): look at Jackie, then
- `Talk: greeting` / `Talk: next context` — test real-VO voiceset contexts.
- `Talking flap: START (shuffle)` + interval slider — the cat-7 talking-face flap (no audio).
- manual category/idle sweeper + `Reset facial`.

Replaced/removed two scratch probes: `JackieFacialTest` and `JackieWorkspotTest` (deleted).

## Open / future
- **Preferred direction (chosen): convert greetings & reactions to real VO voiceset contexts** —
  true lipsync + real voice for free, using game assets. Need to map dialogue beats → context tokens
  (discover Jackie's supported contexts via the `JackieLipsync` cycler).
- The shuffle flap is the fallback for bespoke branching lines that have no matching VO context.
- Not pursued: amplitude/volume-driven jaw (the engine's audio→viseme runs only inside its VO pipeline;
  not reachable for arbitrary Audioware audio) and hand-authored `.scene` lipsync (no JALI tool).

## File map
- `mod/JackieLives/init.lua` — flap engine + dialogue hooks (search `LIP-MOVEMENT flap`).
- `mod/JackieLipsync/init.lua` — standalone test bench.
- `docs/route_b_workspot_plan.md` — abandoned workspot route (kept for reference).
- Memory: `jackie-facial-rig-runtime` — the recipe + values, condensed.

---

## 🔬 OPEN RESEARCH PROJECT (2026-08-13) — real visemes, now that the VO is native

Everything above was written when our audio came from **Audioware**, which carries no facial data.
That premise is gone: since v1.66 the game plays its **own** recording of a chosen line
(`docs/research/native_vo_dialogline.md`). This section is the standing brief for whoever picks
lipsync up next. It is a **research project, not a bug** — the AMM Expressions Overhaul flap looks
good in game, so there is no pressure, only an upside.

**In-game status (2026-08-13):** the flap works; the Voice-lab probes played with **no** mouth
movement at all — expected, because `VO.probe` deliberately bypasses `speakJackieLine` and therefore
never calls `startFlap`. Normal dialogue is unaffected. Do not read the probes as a lipsync
regression.

### What is already solved: the NAME is free

The lipsync animation name is **pure arithmetic from the String ID** — no WolvenKit run, no
extraction, no table to ship:

```
femaleLipsyncAnimationName == "f_" + uppercase hex of the String ID
maleLipsyncAnimationName   == "m_" + uppercase hex of the String ID

jl_1954795386774245380  ->  f_1B20D40C1D405004
```

Verified across every line of `q005_14_after_escape.scene`: **138 of 138 match, zero exceptions.**
(Measured with `redlib` against the local install — the same trick that gave us durations.) So for
any line we can already play, we can already name its exact viseme track.

### What blocks it: nothing binds that animation to the body

- The anims live in an `animAnimSet` that the **scene** binds to the actor —
  `scnActorDef.lipsyncAnimSet`, a `CResourceReference<animAnimSet>`. Outside a scene, nothing binds
  it. This is structurally the same problem as NCLives' workspot carrier `.ent`.
- **No lipsync API exists in the decompiled scripts** — zero hits. Native-only, exactly as
  `DialogLineEvent` was, which is precisely why this is worth a real look rather than a shrug.
- **No public mod does it.** `gh search code` across every CP2077 repo finds the field defined in
  WolvenKit's types and Codeware's imports, and *nobody calling it*. If it were easy it would exist.

### The ladder to try, in order

1. **Resolve the anim set.** Follow `scnActorDef.lipsyncAnimSet` through the scene's
   `resouresReferences` table to a real depot path, and confirm it exists locally
   (`tools/archive_paths.py`). Mac-only work; costs nothing.
2. **Can that anim set reach a spawned NPC?** Either attached at runtime, or riding an `.ent`/`.app`
   we ship. This is the make-or-break step and it is the same class of question as the workspot
   carrier — read `../NCLives/docs/DEPENDENCIES.md` "The pose port" before re-deriving it.
3. **Trigger the named anim on the face rig.** `entAnimationControllerComponent` push-events were
   tried in 2026-06 and did nothing (Route A above). The mechanism that *does* work in this codebase
   is the workspot pair `PlayInDeviceSimple` + `SendJumpToAnimEnt` — try that against the facial rig.

### The strongest lead

`gameObject::PlayVoiceOver(npc, context)` gives **free lipsync** (recorded in
`cp2077-no-runtime-vo-by-string-id`). So the engine demonstrably *can* drive visemes for a voice-over
without a scene — we just can't choose the line that way. **Understanding what that path sets up is
probably the shortest route to step 3**: if `PlayVoiceOver` binds the anim set as a side effect, then
firing it once to prime the body and then playing our chosen line may be all it takes.

That experiment is cheap and needs no new code beyond a CET-console spike.
