# DESIGN — "Jackie Lives" (working title)

## 1. Premise (Option B, chosen)

Jackie Welles is **not killed** at the end of "The Heist." Canonically the game shows him flatlining in
the Delamain cab and (depending on choice) his body going to Vik or Arasaka. Our retcon: he was
critically wounded but **survived**, was quietly **smuggled out of Night City** to recover, and went to
ground. The near-death experience (plus his injuries and Mama Welles) made him **walk away from the merc
life**. Months later, V can find him and bring him home.

He comes back as a **living NPC in Heywood**: tends a bar, helps the old neighborhood as a small-time
**community fixer**. Warm with V, but done with blazes of glory.

## 2. Why this framing is the *feasible* one (reality check)

The whole base game proceeds assuming Jackie is dead — Misty, Vik, the **Ofrenda** in "Heroes," Mama
Welles' grief, etc. Trying to make the **main story** internally consistent with "Jackie's alive" would
mean editing many existing **voiced `.scene` files** and would cascade into quest-dependency breakage.
We **do not** attempt that.

Instead, "Jackie's back" is a **separate, optional layer**: a new questline + a new persistent NPC. The
main story keeps running as written; our content sits beside it. **This is exactly why the "quiet life /
not in main quests" design is correct — it sidesteps the dependency web rather than fighting it.**

Known accepted caveat: the early grief beats (Heroes/Ofrenda) still happened in the player's timeline.
We treat the retrieval quest as **new information delivered later** ("turns out he made it out") rather
than rewriting old scenes. Perfect canon consistency isn't achievable without massive work; "good
enough, delivered as fresh info" is the target.

### Death-flag note (important simplification)
We **do not need to clear Jackie's main-story death fact**. We spawn a **fresh persistent Jackie entity**
for our content. Touching the main-quest death state gains nothing for the quiet-life design and risks
breaking downstream quests. (Jackie's character record/appearance remain loadable after his story death —
AMM can already spawn him anytime.)

## 3. The Quiet Life — how Jackie integrates

- **Default state:** present in the world on a schedule (at his bar / around Heywood / Mama Welles' area),
  doing ambient activity. Probabilistic encounters, not a constant shadow.
- **Interactions:** greets V warmly, can pour V a drink, conditional barks reacting to V's recent story
  progress. May offer small **community-fixer side gigs**.
- **Summon (companion) rules:**
  - Player can call Jackie to a **SIDE job / gig** → he shows up and fights/follows competently using the
    game's stock companion AI.
  - Player tries to call him to a **MAIN quest** → **V declines** ("not pulling Jackie into this mess
    after everything he went through"). Needs a personal/AI voice line (Tier 3).
- **He is NOT a default follower.** Living-city NPC with scheduled presence + conditional dialogue.

## 4. The Retrieval Questline (Tier 2)

Rough beats (to refine):
1. **Trigger / rumor** — sometime after Act 1 / once the player is free-roaming, V hears a rumor or gets
   a message that contradicts the "Jackie's dead" assumption.
2. **Vik's tell** — returning to Vik, instead of his usual line, Vik says *"Oh, didn't you hear?"* and
   hands V an **info shard**: Jackie had to get out of town, current whereabouts unknown.
   - Implementation note: we likely **add** a shard/message + a new optional objective rather than
     rewriting Vik's existing voiced scene. Replacing his branching scene is heavy WolvenKit work and we
     can't easily make new Vik VO. Scope this carefully.
3. **Investigate** — follow the trail (a few objectives/locations) to where Jackie's been lying low.
4. **Extraction / reunion** — bring him back; he explains he's out of the life now.
5. **Settle in** — Jackie becomes the persistent Heywood bar/fixer NPC (flips a "Jackie returned" state).

## 5. Summon layer — design preference

Prefer building our **own thin summon layer** (Codeware + game companion/`AICommandSquad` systems, or
AMM's API) over patching the third-party "FOLLOWER JACKSTER" mod's internals. Reasons: maintainability,
no dependency on another mod's gating, and we control the main-quest ban. We'll still **study** the
Act 1 companion mod and AMM as references for how the follower AI is wired.

Main-quest ban implementation idea: on summon, query the **JournalManager** for the active/tracked quest
and check its **type** (main vs side/gig). If main → refuse + play V's decline line. Maintain a small
blocklist of main-quest journal paths as a fallback.

## 6. Content system

The planned **~1000 messages** of branching V↔Jackie conversation (filling him in on the main story, him
commenting) is **writing-heavy but engineering-light**. Build a **data-driven dialogue system** (dialogue
trees in data files, gated by quest facts) so content can be authored without touching code. Tier 3.

## 7. Priority tiers

- **Tier 1 — Framework & functionality:** runtime stack working; Jackie as a persistent living NPC with
  scheduled presence at 2–3 Heywood spots; summon-on-side-job via companion AI; hard **main-quest ban**;
  a **"Jackie returned" state flag**. ("Jackie exists and behaves.")
- **Tier 2 — Immersion:** the retrieval questline; Vik info shard; scheduled/probabilistic encounters;
  conditional greetings/barks; pour-a-drink interaction.
- **Tier 3 — Details & fun:** AI/custom voice lines (incl. V's main-quest decline line); the branching
  text conversations; small community-fixer side gigs; polish.

## 8. MVP (prove feasibility fast, before any tier work)

- **MVP-0 — Proof of life:** via CET (Lua), spawn a **persistent** Jackie NPC at a fixed Heywood spot
  (e.g. near El Coyote Cojo / Mama Welles'). Confirm model, appearance, and that he persists. Idle/ambient.
- **MVP-1 — Summonable follower:** make Jackie follow/fight via the companion AI, **decoupled** from the
  Act 1 gating (so it works post-Act 1).
- **MVP-2 — Main-quest ban:** detect active main quest and refuse the summon (placeholder text line).
- **MVP-3 — Return flag:** a debug flag that flips Jackie from "hidden" to "present at the bar," standing
  in for the eventual quest trigger.

## 9. Decisions made / still open

**Resolved:**
- Platform = **Steam**, build = **Patch 2.3 / 2.31** (Oct 2025). Full core mod stack supports it. See `SETUP.md`.
- Mod manager = **Vortex** for the dependency stack.
- Vik beat = **add an info shard + new objective**, do NOT rewrite his voiced scene.
- Revival arc **gates on the "send Jackie to Vik" body choice** at the end of The Heist. The other two
  choices lead to his canonical death (no revival). This gives a clean narrative branch.

**Still open:**
- Exact "return" trigger timing (post-Act-1 vs later) for the retrieval quest.
- How to handle the existing **mourning** content (see §10.3 — likely targeted scene/quest suppression,
  not just a flag).
- Verify whether the **"Heroes" / ofrenda** quest is gated on the body choice; if not, it still fires and
  needs handling.

## 10. Detail-ideas integration & reality-checks
Source brainstorm: `docs/detail_ideas.txt`. Captured + reality-checked below.

### 10.1 Probabilistic location schedule ("Where is Jackie")
Jackie has a `JackieCurrentState` that picks among locations: his bar, El Coyote Cojo, Mama Welles' place
(sleeps there), favorite restaurant, the noodle place, Misty's, Vik's, Afterlife, Lizzie's, Delamain's
workshop, plus Sleeping / Unavailable. Scarcity matters — not always available, can ignore calls / reply
late. Long-term aim: a **relationship simulation**.
- **MVP:** instant despawn/spawn driven by the schedule state. Only instantiate him when V actually
  arrives at his current location (don't load/render his spot otherwise — this is how the game already
  streams NPCs).
- **Tier 2 sub-project — realistic movement:** travel time + cool-off between locations (fast-travel
  across town ≠ instantly there), arrival by bike around a corner rather than popping in. **This is the
  most ambitious system in the whole mod — honestly hard.** Stage it after the basics work, and lean on
  whatever the base game already uses for companion/romance NPC presence rather than rebuilding it.
- **Mama Welles' house interior:** her home reportedly has no interior inside map bounds, so it'd need a
  new interior placed in an empty Heywood building (advanced ArchiveXL world-building). **Defer** — for
  the schedule, start with locations that already have accessible interiors; add the house later.

### 10.2 Voice lines (the heart of "feeling alive")
Reuse Jackie's existing ~1000 original voice lines (catalogued at sounddb.redmodding.org) — no new plot we
can't cover. Categories: greetings, environmental comments, combat reactions, idle remarks, emotional
acknowledgements, short banter, romance moments.
- **Feasible and the right instinct.** Jackie already uses these via the game's scene/bark/VO system in
  his existing appearances. Plan: learn that existing trigger system and **extend it** to our new
  locations/states rather than inventing one. Investigate how the game randomizes ambient barks (to keep
  greetings from getting repetitive — likely a chance/cooldown the existing system already supports).
- **Supporting tool (Claude can build this):** a small **local web app** (phone-friendly) to audition
  lines and tag each with usable moments / trigger conditions / mood / probability. This is plain web dev,
  fully decoupled from the game — low risk, high value. Good Tier 2 companion task to the cataloguing work.

### 10.3 Removing the mourning (answer to "will suppressing dead flags work?")
**Honest reality-check: suppressing a death flag alone will NOT reliably stop the mourning.** Mama Welles'
ofrenda (Heroes), Misty's grief, Vik's lines, and the gift/bike texts are **scripted into specific quest
phases/scenes** that fire on quest progression — not gated on a runtime "is Jackie dead?" boolean that
NPCs re-check. So removing mourning means **targeted suppression of those specific scenes / quest phases /
journal entries**, i.e. the hand quest-patching you've signed up for — not a single flag flip.
- **Tier 2:** Mama Welles, Vik, Misty mourning content.
- **Tier 3:** scattered Jackie mentions (Takemura etc.) — much harder, lower priority.

### 10.4 Why "Jackie never comments on the Relic arc" is already solved by our architecture
Lore rationale: V deliberately keeps him out of it — she knows if he learned she was dying he couldn't
help but throw himself back into danger, so she protects him by leaving him in peace. **This maps cleanly
onto the design we already chose:** he's banned from main quests and V *declines* to summon him there. So
his absence from Relic beats is intentional and in-character — no extra system needed; the decline line
carries the rationale.

### 10.5 Jackie's bike
He wants his bike back. Options, easiest first:
- **Easiest:** V never receives the keys — suppress the Mama Welles "gift/package" texts entirely, so
  there's nothing to hand back.
- **Immersive:** a short SMS where Jackie asks for his keys, then remove them from V's inventory (hand
  over on next meeting, or via a drop point).
- Defer to Tier 2/3.

### 10.6 Romance (later sub-mod)
Romanceable Jackie as a **separate later sub-mod** built on the relationship-sim layer; reuse his
existing affectionate voice lines. Out of scope until the living-NPC + voice systems exist.

### 10.7 Scope reality
Antonia is willing to invest tens of hours in hand-crafted state management + quest patching, with voice
cataloguing as a major part. That's the right expectation — the engineering is mostly **wiring + content**,
and the hardest single piece is the realistic city-movement system (§10.1), which we stage last.
