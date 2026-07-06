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
Jackie's body destination at the end of The Heist gates the ofrenda. From research (confirm exact
values via Fact Finder / JLFactDump during the Heist run):
- `q005_jackie_to_hospital` — body to Vik / hospital.
- `q005_jackie_to_mama` — body to Mama Welles → **this is what enables the ofrenda ("Heroes")**.
- `q005_jackie_stay_notell` — body left at the No-Tell Motel.
> We do **not** edit these (they're the player's canon choice). We suppress the downstream mourning.

## The edit list

| # | Mourning beat | Suspected resource (CONFIRM in WolvenKit) | Method | Owner |
|---|---------------|-------------------------------------------|--------|-------|
| 1 | **"Heroes" — ofrenda/wake** (Mama invites V → El Coyote → place guns/photo → talk to Misty/Mama/guests) | Side-job quest, likely `sq030_*` (**ID UNCONFIRMED**) + its `.scene`s | **A** — CET fact-block its start; **fallback** WolvenKit `.questphase` edit if it auto-starts | Claude (CET) / Antonia (find ID) |
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

## Build status
- [ ] #1 Heroes fact-block — **needs the quest ID/start fact first** (datamining). Then Claude writes it.
- [ ] #3 Vik scene edit — needs scene path; Antonia edits in WolvenKit with Claude's steps.
- [ ] #4 Misty scene edit — needs scene path; as above.
- [ ] Rewards decision (pistols/bike).
- [x] #5 explicitly deferred (Tier 3).

> ⚠️ These edits are Quiet-Life content. Keep them gated so they don't fight a future Blaze build
> (in Blaze the death never happens). Simplest: run the Heroes block whenever the mod is active and
> Jackie is (or will be) alive — it's idempotent and harmless if Heroes was never going to fire.
