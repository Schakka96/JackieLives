# Mourning suppression worklist — "Quiet Life" mode

_Created 2026-07-06. The concrete edit list for removing the "Jackie is dead" mourning content so it
doesn't contradict a living Jackie. Decided approach: **A+B hybrid** (runtime fact-block the big
quest in CET; hand-edit the standalone grief scenes in WolvenKit; defer the scattered one-offs)._

## When this applies
- **Quiet Life mode:** REQUIRED. Vanilla Jackie still "died," so all of this fires and must be suppressed.
- **Blaze of Glory mode:** mostly **auto-suppressed** — if Jackie escapes the Heist alive, the death
  body-choice facts never get set, so the ofrenda/grief that's gated on them never triggers. (Still
  worth a spot-check after Blaze is built.)

## The interacting Heist facts (the root)
Jackie's body destination at the end of The Heist gates the ofrenda. **CONFIRMED present in the
sq018 binaries** (`strings` on `docs/mounring_scenes/`):
- `q005_jackie_to_hospital` — body to Vik / hospital.
- `q005_jackie_to_mama` — body to Mama Welles → **this is what enables the ofrenda ("Heroes")**.
- `q005_jackie_stay_notell` — body left at the No-Tell Motel.
> We do **not** edit these (they're the player's canon choice). We suppress the downstream mourning.
> The CET framework hard-blocks all three via `JL_MOURNING_PROTECTED` so a bad list row can't touch them.

## Confirmed from the extracted binaries (2026-07-07)
`strings` on `docs/mounring_scenes/` (no JSON needed for this pass):
- **`sq018` IS the "Heroes" ofrenda quest** — the scene contains *"I'm having an ofrenda for Jackie"*.
  (Supersedes the earlier `sq030` guess.)
- Quest-run facts seen: **`sq018_active`**, **`sq018_01_funeral_preparations`**, `sq018_01_ofrenda`,
  `sq018_03_ofrenda`. Pinning `sq018_active`→0 is the chosen runtime lever (Heroes is a narrative
  dead-end, not a prerequisite → low risk).
- Misty/Mama **world-bark** grief runs off their own default-scene state (`misty_default_*` incl.
  `emotional_gesture__grief__female` anims, `mama_welles_default_talked`) — Tier-3, left for later.
- **No single "jackie_dead" master fact exists** — grief is gated per-scene on the body-choice facts.
- ⚠️ Exact numeric fact VALUES are still `strings`-truncated → CONFIRM via the .questphase JSON
  (WolvenKit CLI — GUI right-click convert fails on questphases in this build) or in-game preview.

## The edit list

| # | Mourning beat | Suspected resource (CONFIRM in WolvenKit) | Method | Owner |
|---|---------------|-------------------------------------------|--------|-------|
| 1 | **"Heroes" — ofrenda/wake** (Mama invites V → El Coyote → place guns/photo → talk to Misty/Mama/guests) | **CONFIRMED `sq018`** — `sq018/scenes/sq018_01_mama_welles.scene`, `sq018_03a_misty.scene`, `sq018_00_mama_welles_holocall.scene`; phase `sq018/phases/sq018_01_mama_welles.questphase` | **A** — CET pin `sq018_active`→0 (built, WIP); **fallback** WolvenKit `.questphase` edit | Claude (CET) / Antonia (JSON+value) |
| 2 | **Mama Welles "gift" texts** (Jackie's belongings / bike / pistols) | Phone messages fired from/after Heroes | Blocked as a side effect of #1; verify none fire independently | Claude / Antonia |
| 3 | **Vik's grief lines** (post-Heist clinic visit) | Vik clinic `.scene` (search VO/strings for Jackie grief) | **B** — WolvenKit scene-node edit: reroute past the grief section | Antonia (WolvenKit) |
| 4 | **Misty's grief lines** (Esoterica, post-Heist) | Misty Esoterica `.scene` | **B** — WolvenKit scene-node edit | Antonia (WolvenKit) |
| 5 | **Scattered one-off "he's dead" mentions** (Takemura, Judy, random barks) | Many scenes | **DEFER (Tier 3)** — accept per DESIGN §10.3 | — |

## Rewards we'd lose by blocking "Heroes" (open decision)
"Heroes" is the normal source of **La Chingona Dorada** (Jackie's iconic pistols) and the path to
**Jackie's Arch bike** (delivered via post-quest Mama Welles texts). **CONFIRM the exact reward list +
delivery.** Options once Heroes is blocked:
- (a) Accept the loss (the mod already has its own "give Jackie's bike back" beat).
- (b) Re-grant the pistols/bike another way (CET `GiveItem` on the reunion, or a Jackie hand-off).
- **Decision needed from Antonia.**

## Datamining checklist (do alongside the JLFactDump spike, on Windows)
You'll already be in CET/WolvenKit for the spike — capture these too:
1. **Heroes' quest ID + start fact:** with **Fact Finder** (nexus 12735) active, trigger/approach the
   ofrenda and note the fact(s) that flip when it becomes available. That tells us if it's fact-blockable.
2. **Vik grief scene path:** in WolvenKit, search the archives for Vik's clinic scene / Jackie-grief VO
   strings; note the `.scene` path + the node that holds the grief lines.
3. **Misty grief scene path:** same for the Esoterica.
4. **Heroes reward records:** confirm La Chingona Dorada + Arch bike delivery.
Send me the IDs and I'll write the exact CET fact-block (#1/#2) and the step-by-step WolvenKit node
edits for #3/#4.

## Values confirmed from the questphase JSONs (2026-07-07)
- **`sq018_active > 0`** is the ofrenda phase gate → **pin to 0 blocks all of Heroes.** [CONFIRMED]
- Mama grief calls are requested by **`holo_mama_welles_calls_v_start_activate` / `_end_activate` = 1**,
  firing while shared **`holo_setup_active < 1`**. Pin the request facts to 0. Mama = grief-only → safe.
  ⚠️ **Never pin `holo_setup_active`** — it's the shared holocall system (breaks ALL calls).
- Misty grief calls use **`holo_misty_calls_v_*_activate`**, but Misty also calls for Evelyn/tarot →
  left commented until proven Jackie-only.
- **Misty's WORLD dialogue grief is NOT fact-pinnable.** `misty_default.scene` branches on quest
  PROGRESS (`q005_active`, `q101_done`, `q112_done`, `sq018_03_done`, `sq018_03a_misty_invited`), not a
  toggleable grief flag → her somber lines are baked into the post-Heist chapter. Removing specific
  lines = **manual scene-node edit only** (Tier-3, subjective). The ofrenda-linked branches
  (`sq018_03_*`) are already dead once we block sq018.

## Build status
- [x] **CET framework BUILT + CONFIRMED** (v0.97, `init.lua`) — data-driven `JL_MOURNING_FACTS`
  (values now real, not guesses), safe-by-default toggle (`JL.mourningSuppress`, persisted),
  body-choice guard (`JL_MOURNING_PROTECTED`), dry-run **Preview** + **Apply once**, ~5 s re-assert.
- [x] #1 Heroes fact-block — `sq018_active`→0. **CONFIRMED.** Ready to test (Preview → enable).
- [x] #2 Mama grief calls — `holo_mama_welles_calls_v_*_activate`→0. **CONFIRMED.** Ready to test.
- [ ] #3 Vik scene edit — **NOT in the current dump.** Search WolvenKit for **`vector`** / `victor_vector`
  / `ripperdoc` (he is "vector" internally — that's why vik/vic/vek found nothing).
- [~] #4 Misty scene edit — ambient world grief is quest-progress-keyed (see above) → Tier-3 manual,
  subjective. Recommend defer/accept per DESIGN §10.3.
- [ ] Rewards + side-effect decision (see below).
- [x] #5 explicitly deferred (Tier 3).

## ⚠️ Side effect of blocking sq018 (decide)
The sq018 questphase also SETS `mama_welles_default_on=1`, `coyote_community_activated=1`,
`elcoyote_barman_default_on=1` — i.e. Heroes is what "opens" El Coyote Cojo as an active location with
Mama tending bar. Blocking sq018 means **Mama never activates at El Coyote** and its rewards
(**La Chingona Dorada** pistols) don't deliver. For "Jackie secretly lives" that's arguably *correct*
(a memorial bar is itself mourning), but it removes a vendor/location. Options: (a) accept; (b) re-grant
the pistols via CET on the reunion. **Decision needed.**

> ⚠️ These edits are Quiet-Life content. Keep them gated so they don't fight a future Blaze build
> (in Blaze the death never happens). Simplest: run the Heroes block whenever the mod is active and
> Jackie is (or will be) alive — it's idempotent and harmless if Heroes was never going to fire.
