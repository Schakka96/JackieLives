# q005/q101 graph read — findings & verdict (2026-07-06)

_From Antonia's WolvenKit JSON export of the full q005 + q101 quest trees (`q005_raw/`, `q101_raw/`
— exports kept out of git; see `q005_graph_extract.md` for how they were pulled). Analysis by
tracing fact-setter (`questSetVar_NodeType`) and condition (`questFactsDBCondition`) nodes across
all 88 phase files._

## VERDICT: "keep all 3" is feasible — and needs NO quest-graph surgery.

The go/no-go asked whether the "Heist complete → Watson unlocks" path is separable from the
"biochip → Jackie dies → q101/Johnny" branch. The graph shows there is **no clean seam inside the
vanilla graph** (the Watson unlock is authored *inside* q101, not at q005's end) — BUT that doesn't
matter, because **every lever we need is a plain settable fact, and q005 itself never installs
Johnny.** So instead of editing the graph, the mod sets the facts directly and never enters q101.
This is the same mod-side / standalone-what-if approach the project already chose for the Blaze
set-piece (`DESIGN.md §11`), now with the exact facts to flip.

## The key levers (exact fact names, harvested from the graph)

### Watson barrier — THE lever
- **`watson_prolog_unlock = 1`** and **`watson_prolog_lock = 0`**.
- Set in vanilla inside **`q101_j_01_concert.questphase`** (the Love Like Fire / Johnny concert
  memory) — which is exactly why the world visibly opens at Love Like Fire (matches Antonia's live
  observation and the JLFactDump timing).
- **Read by NO quest condition** anywhere in q005/q101 → the placed *prevention-area system*
  consumes them directly. That makes them a clean toggle: set them from the mod and Watson opens,
  no q101 required. (Confidence: high; cheap in-game confirm = set the fact, drive to a Watson exit,
  barrier gone.)

### Johnny / biochip / death — all AFTER q005, in the No-Tell → q101 tail
- q005 does **NOT** set any johnny/relic/biochip-install fact. The chip is just an item V carries.
- In-data Jackie even **survives the escape**: `q005_jackie_follower_escape = 1`
  (`q005_06_escape.questphase`). His death + V's death (→ biochip activation → Johnny) are the
  **No-Tell Motel tail** (`q005_09_no_tell_motel.questphase`) that flows into q101.
- **q101 is entered only when q005 completes and the main-quest graph advances to it** — no fact
  force-starts it (only `q101_got_q005_completion_achiv`, an achievement flag). A Blaze what-if that
  never runs the real q005 tail therefore **never enters q101 → no Johnny, guaranteed.**

### Act-2 content toggles also gated inside q101 (the "sparse world" cost — and its fix)
Skipping q101 leaves these OFF, but they're all plain `_on` toggle facts we can replicate from the
mod (harvested from the q101 phases). Enumerated set:
- `apartment_on` (V's apartment) · `victor_vector_default_on` (Vik) · `misty_default_on` +
  `mq033_misty_dialogue_on` (Misty) · `wat_lch_gunsmith_01_default_on` (a Watson gunsmith) ·
  `radio_on` · `tv_on` · `cyberspace_on`.
- ⇒ The "Watson-only sparse sandbox" worry shrinks to "which toggles we choose to also set."

## The resulting build (mod-side, no WolvenKit graph edit)
Extends the existing Blaze what-if (`blaze.lua`) at its end:
1. Set `watson_prolog_unlock=1`, `watson_prolog_lock=0` → Watson opens.
2. Optionally set the content toggles above (apartment/Vik/Misty/vendor/radio/tv) to un-sparse it.
3. Never trigger q101 (already the case — Blaze never completes the real q005) → no Johnny/biochip/death.
4. Custom "wake at Vik's" via the existing reunion machinery (`reunionMeetTree`/`completeReunion()`).
5. Mourning auto-suppressed — no body-destination facts are ever set (as `mourning_suppression.md`
   predicted for Blaze).

## Honest caveat (test incrementally)
We'd be opening Watson + toggling content with **no main quest running** — unusual state. Risk is
low (these are presence/prevention toggles, not story-progression facts, and the wiki's "facts break
things" warning targets story facts), but confirm in this order on a throwaway save: set
`watson_prolog_unlock` alone → verify Watson opens, no soft-lock, save/reload clean → then layer the
content toggles one at a time.

## Follow-up findings (2026-07-07, from in-game tests + deeper trace)
- **Watson barrier lever CONFIRMED in-game:** setting `watson_prolog_unlock=1` + `watson_prolog_lock=0`
  physically removes the district barriers on an Act-1 save; game does not break. ✅
- **BUT the open-world CONTENT (gigs, NCPD, map markers, sidequests) does NOT come back** — it is not
  in q005/q101 at all. It lives in the open-world quest system and is gated on the **main quest's
  journal/progress state actually reaching Act 2** (no single "act2_on" fact exists). Content toggles
  (`apartment_on`, `*_default_on`, `sts_loop_start`, etc.) restore some NPCs/vendors but NOT the map
  content. This is the "sparse Watson sandbox" the early research predicted, now confirmed live.
- **Johnny cannot be decoupled from Act 2 / re-gated.** He is authored INLINE across **17 distinct
  q101 scenes** (landfill, Vik garage, V-room, the whole `q101_j_*` concert memory). There is NO single
  "johnny unlock" fact — only local scene-state (`q101_johnny_char_entry`, `q101_johnny_past`). You
  cannot complete Playing for Time without him, and `watson_prolog_unlock` is itself set *inside*
  `q101_j_01_concert`. ⇒ "finish PfT but gate Johnny to a never-event" is infeasible (would need editing
  all 17 scenes).
- **Conclusion:** "full vanilla open world + no Johnny" is not achievable. Two real paths remain:
  - **A — No-Johnny sandbox** (Blaze): barrier down + custom content. Richness TBD.
  - **B — Full game + Jackie revived** (Quiet Life, already built): Johnny + death clock present.
- **DECIDING TEST for Path A:** export the open-world manager / gig / NCPD quests (`open_world`, `sts`,
  `gig` searches) → trace whether the gig+NCPD system can be switched on independently of the main
  Act-2 plot. If yes, Path A is a real game; if no, it stays quiet.

## Status
- [x] Graph exported + read; levers identified.
- [x] Blaze-end Watson-unlock slice built + **confirmed in-game** (barrier lifts, no break).
- [ ] **NEXT — open-world activation datamine** (the Path-A decider): export `open_world`/`sts`/`gig`
  quests, trace gig+NCPD gating (fact = forgeable → rich sandbox; main-quest journal = not → thin).
- [ ] Then: decide Path A vs B; if A, build out the sandbox content + wake-at-Vik's scene.
