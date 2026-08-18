# "Ghost in the Machine" — the Jackie rehabilitation questline (design)

_Written 2026-08-18, after WolvenKit's command-line tool landed on the Windows box._
_Companion docs: `DESIGN.md` §11 (Blaze), `BLAZE_WOLVENKIT_OBJECTIVES.md` (journal how-to),_
_`research/texting_research.md` (SMS), `research/shard_placement_research.md` (shards)._

---

## 0. What actually changed, and what didn't

**The question:** now that WolvenKit's CLI is installed on Windows, can the mod carry a *real*
questline instead of the current on-screen-text stand-in?

**Yes — and the pipeline for it already exists.** `tools/build_archive.py` already writes
CR2W-JSON on the Mac (plain text Claude can author) and shells out to `WolvenKit.CLI.exe` on
Windows to pack it into `JackieLives.archive`. That path is *already shipping* — it's how the
female-V voice map gets into the game. Adding a quest means adding more files to the same folder
and running the same build. No new tooling, no new dependency for players.

### What the CLI unlocks (things that were flatly impossible before)

| Capability | What the player sees | Status before |
|---|---|---|
| **Real journal quest** (`.journal` resource) | A named quest in the Journal with ticking objectives in the HUD tracker, the "Quest updated" chime, and a permanent record | Faked with the blue message band, which vanishes and leaves no trace |
| **Real phone SMS** | Jackie texts V. Thread lives in the phone, with the unread badge | **Impossible at runtime** — confirmed, messages must be authored into an archive (memory: `cp2077-sms-needs-an-archive`) |
| **Real readable shards** | A shard case V picks up; the text lands in the Codex and stays there | Faked with a proximity popup that shows once and is gone |
| **Custom localisation strings** | All of the above translated (JA/ES already established) | Only for Lua-authored text |

### What it does *not* unlock — the honest ceiling

1. **No new voice for anyone.** Jackie's dialogue is limited, permanently, to the ~1200 lines he
   actually recorded (`vo_library/jackie.csv`). Same for Vik, Misty, Mama, Nix. The CLI packs
   files; it does not make a voice actor. **This is the single biggest constraint on the story
   and it shapes every beat below.**
2. **No new cutscenes.** Authoring a `.scene` from scratch (branching graph, camera, lipsync,
   timing) is a different order of difficulty from everything this mod has done —
   `wolvenkit_scene_editing.md` is a *reading* guide, and even deleting a line from an existing
   scene was fiddly. Treat scene authoring as out of scope.
3. **No new animations, no new faces, no new locations.** Everything happens in places the game
   already streams, using bodies the game already has.

### The design rule that follows from the ceiling

> **Voice for what Jackie can really say. Text for everything else.**

Jackie speaks through the existing library (which is deep — `tools/v_index.py` and the line
library make finding a usable take fast). Every *other* character communicates by **SMS, shard,
or journal entry** — because a subtitle with no voice behind it reads as broken, whereas a text
message reads as a text message. This is not a compromise forced on the story; it is genuinely
how these people would communicate about a thing they're hiding.

---

## 1. The premise

The existing retrieval quest (`retrieval.lua`, stages LOCKED → REUNITED) ends with Jackie alive,
out of the life, and back with V. It's a good ending, and it stays exactly as it is — it becomes
**Act I**. What it never answers is: *how* is he alive, and what did it cost.

**The answer, and the spine of the new series:** Vik had a dying man on the table and no time. To
keep him breathing he used what he could get in the hours he had — **salvaged Arasaka
military-spec chrome**, pulled from the same heist that killed him. It worked. It also left two
things inside Jackie that belong to Arasaka:

- **The beacon.** Arasaka's factory anti-theft telemetry — mil-spec parts phone home. Nobody was
  listening at first. Someone is listening now. *Jackie is traceable.*
- **The passenger.** During the Konpeki firefight an Arasaka security netrunner burned a
  suppression daemon into his OS. It never finished executing, because he flatlined mid-attack —
  so it's still sitting there, resident, waking up a little more each month. *Jackie's own chrome
  is turning against him.*

Two threads, deliberately different in flavour: **the beacon is an external threat** (they can
find him → fights, tension, a reason to move), **the passenger is an internal one** (he can't
trust his own hands → dread, medical stakes, the actual "rehabilitation"). They converge at the
end, where the fix for one makes the other worse.

**Working title:** *Ghost in the Machine*. (Alt: *Salvage*, which is better thematically — he's
made of it, and he is it.)

---

## 2. Structure

Five parts, each self-contained and each ending at a stable resting state, so a player who stops
after Part 2 is not left mid-sentence. Progress persists in one game fact, exactly like the
existing questline (`jackielives_arc`, 0–5) — never renamed, for the same reason
`jackielives_stage` is never renamed.

Parts are **paced by lived time, not by a quest marker**: each one arms after N in-game days
*and* a familiarity threshold since the previous. Jackie's deterioration should feel like
something happening to a friend you're already living with, not a to-do list.

```
Act I (SHIPPED)   retrieval.lua                        Jackie is alive and back
   │
   ▼
Part 1  STATIC     the first episode; Vik's scan       the reveal — two things inside him
   │
   ▼
Part 2  PHONE HOME the beacon; Arasaka comes looking   heat system + snatch-squad fights
   │
   ▼
Part 3  PASSENGER  the daemon; it takes his hands      the horror beat + the money problem
   │
   ▼
Part 4  SALVAGE    the operation                       three endings, permanently different Jackie
   │
   ▼
Part 5  AFTER      (epilogue, ending-dependent)        Mama's table / the maintenance ritual / the raid
```

---

## 3. The parts

### Part 1 — "Static"  *(the reveal)*

**Arms:** 3 in-game days after REUNITED, with familiarity above the "he's comfortable around you"
tier. **Trigger:** the first time Jackie is following V outdoors afterwards.

1. **The episode.** Mid-follow, Jackie stops walking. Hand spasms — reuse the existing
   halt + workspot machinery; a held gesture animation reads fine. Two seconds of audio glitch
   (a library line cut short, then re-fired), and a short screen distortion. He shrugs it off with
   a real line — the library has deflection takes.
2. **The text, that night.** SMS from Jackie: it's happened before. Three times. *Don't tell
   Misty.* — This is the moment the SMS system justifies its build cost: it's private, it's
   deniable, it's the way someone hides a symptom.
3. **The objective.** *Take Jackie to Vik.* Real journal objective, real tracker. Jackie already
   follows V and already rides along; nothing new is needed to move him there.
4. **The scan.** At Vik's, the reveal lands as a **shard — "Ripperdoc scan, patient: J. Welles"**,
   picked up off the counter and kept in the Codex. Written as Vik's clinical notes: two foreign
   objects, one broadcasting, one dormant-but-not-dormant, and one sentence of Vik being Vik about
   what he had to work with that night.
5. **The framing choice** (dialogue, Jackie voiced from the library): *pull the Arasaka chrome now*
   — Vik says he'd survive it and be a shadow of himself — or *find the proper fix*. Choosing
   "pull it now" doesn't skip the series; Vik refuses to do it blind, and it sets a flag that
   colours Jackie's lines for the rest of the arc (he *wanted* out early).

**Ends at:** V and Jackie both know. Nobody else does.

**Build cost:** low. One journal quest + 4 objectives, one SMS, one shard, one dialogue tree, one
scripted stumble. Everything reuses shipped systems.

---

### Part 2 — "Phone Home"  *(the beacon — the traceability thread)*

This is where the premise becomes a **mechanic instead of a paragraph**, which is the difference
between a story the player is told and one they play.

**The heat system.** A hidden counter, `jackielives_trace`, accrues while Jackie is out in the
world with V — faster in Watson and the city centre (dense Arasaka presence), slower in the
Badlands, near-zero when he's at home. Three thresholds:

| Heat | What happens |
|---|---|
| Low | An SMS from an unknown number. Then nothing. |
| Mid | A **surveillance drone** overhead where Jackie idles. Shoot it or leave; either way it's seen him. |
| High | An **Arasaka snatch squad** spawns and comes for him. |

The squad is the cheapest good fight in the project: the **actual heist kill-squad records are
already harvested and verified** — `Character.q005_arasaka_kill_squad_4_officer` and friends,
from the base-game scene files (TODO v1.58). They're lore-correct, they're real records, and
`blaze.lua` already proves the spawn-hostiles-and-let-Jackie-fight-beside-V pattern works.
Companion combat is shipped. **This beat is mostly assembly, not invention.**

Crucially: **heat keeps rising until the player deals with it.** The quest isn't a marker on a
map, it's a problem that follows them home.

**The beats.**
1. **Confirmation** — after the first squad, Jackie names it. He knows what a corp snatch team
   looks like; he's the one who says out loud that they came for *him*.
2. **The netrunner.** V needs someone who can read a corp telemetry handshake. **Nix at the
   Afterlife** is the right call — established, accessible, no romance/quest entanglement, and
   canonically the guy you take weird chrome to. He communicates by **shard/SMS** (no VO).
   Cost: eddies, or a favour.
3. **The relay.** The beacon doesn't talk to Arasaka Tower directly; it talks to whatever comms
   mast it can see. Drive out with Jackie, plant Nix's jammer at a mast — proximity objective at a
   captured coordinate, the same pattern the retrieval hideout already uses. Ambush optional.
4. **The choice.**
   - **Burn it.** The beacon dies. Heat stops accruing and resets to zero. But a mil-spec unit
     going dark is itself a data point — Arasaka logs a dead beacon, and Part 5's raid becomes
     possible.
   - **Spoof it.** Nix feeds it a loop: Jackie reads as a body in transit, catalogued and
     unremarkable. Heat freezes but never resets, and the spoof degrades — one late-arc squad
     fires no matter what. Safer now, unresolved later.

**Ends at:** Jackie can walk through Night City again. The *other* problem hasn't gone anywhere.

**Build cost:** medium — the heat system and the drone are new, the fights are assembly.

---

### Part 3 — "Passenger"  *(the daemon — the rehabilitation thread)*

The horror beat, and the reason the series is called what it's called.

1. **Escalation, in three stages**, spread across days: the stumble becomes a blackout (he loses
   ten minutes and lies about it — the lie is checkable in his own SMS timestamps, which is a
   lovely thing text can do that voice can't), the blackout becomes a **weapon discharge**, and
   then:
2. **The takeover.** Somewhere controlled — his own place, not a street — Jackie's chrome takes
   his hands for about twenty seconds. He goes hostile, says nothing (the daemon isn't him), and
   then drops. Attitude-flip is already a solved mechanic in this codebase.
   **This ships behind `Config.arc.takeover = true` and a clear warning in the settings**, because
   for a player who has spent forty hours with this character as a friend it is genuinely upsetting,
   and that should be their call, not ours. With it off, the beat is a near-miss instead: he gets
   the gun halfway up and fights it back down.
3. **Vik taps out.** Shard: he can trap the daemon or take out the chrome, not both, and he can't
   do either alone. The daemon has spent a year running on Jackie's neural pattern — pulling it
   pulls some of him with it. *This is the sentence the whole series is built to earn.*
4. **The money.** Replacement chrome that isn't Arasaka's costs more than either of them has.
   One gig, Jackie fighting beside V — an existing pattern, and thematically pointed: the man
   who's done with the merc life takes one more job to pay for getting out of it.
5. **The people.** Two optional beats, both text-and-presence rather than dialogue:
   **Misty** works out something's wrong (the tarot beat writes itself, and her post-reunion shard
   already establishes her voice on paper); **Mama Welles** must not find out, which the dinner
   system can dramatise for free — a dinner where Jackie's hand shakes at her table.

**Ends at:** the operation is funded and scheduled. Jackie is afraid, and says so once, in his
own voice, because the library has that take.

**Build cost:** medium. The escalation ladder and the takeover are new; the gig and the dinner are
existing systems pointed at a story.

---

### Part 4 — "Salvage"  *(the operation, and the three endings)*

One scene, one choice, permanent consequences. The choice is **V's to make only because Jackie
asks them to make it** — he doesn't want it to be his, which is both in character and the most
uncomfortable thing in the questline.

| Ending | The operation | The Jackie you live with afterwards |
|---|---|---|
| **A — Clean** | Everything Arasaka comes out. The daemon goes with it, and takes the edge with it. | Ordinary. Weaker in a fight, tires, declines gigs, found at El Coyote more than on the street. The shard's promise kept: *he's done with the merc life, for real.* |
| **B — Caged** | The daemon is walled off, the chrome stays. | The companion you already know — but it needs upkeep: flare-ups on a timer, periodic ripper visits, an ongoing small system rather than a resolved one. Alive, not cured. |
| **C — Ride it** | Refuse. Walk out. | Strongest Jackie in the mod. Heat never stops. Arasaka comes for him properly in Part 5, and that fight is the hardest thing the mod contains. |

All three are **defensible and none is the "good" one**, which is the only way a choice like this
is worth building. A persists as `jackielives_arc_end`, and every companion system reads it.

**Build cost:** low-medium — the choice UI and facts are shipped tech; the *content* is the work,
because three durable variants of a companion is three times the tuning.

---

### Part 5 — "After"  *(epilogue, branches by ending)*

- **A →** Mama's table. The dinner system, with the plate that has always been waiting. Quiet,
  and the whole series pays out here.
- **B →** the ritual. A recurring low-key errand that keeps him steady; the mod's first *ongoing*
  obligation rather than a completed quest, which suits the theme exactly.
- **C →** the raid. Arasaka comes to wherever Jackie sleeps, in force. The one genuine set-piece —
  and the one place a boss-tier spawn is earned rather than decorative.

---

## 4. Feasibility, stated plainly

| Piece | Difficulty | Why |
|---|---|---|
| Journal quest + tracked objectives | **Medium** | New territory, but `BLAZE_WOLVENKIT_OBJECTIVES.md` already maps it and the archive build is shipping |
| SMS threads | **Medium** | Needs the archive-authored thread + Lua scheduling; `texting_research.md` says feasible, one unknown (Lua vs. a redscript shim) to spike first |
| Readable shards | **Medium** | Item record + action record + localisation are text (authorable on the Mac); only the journal onscreen entry needs the CLI |
| Arasaka squad fights | **Easy** | Records harvested and verified; `blaze.lua` proves the pattern; companion combat shipped |
| Heat system, triggers, facts, choices, endings | **Easy** | All of it is systems this mod already runs |
| Drone flyover | **Easy-medium** | Spawn-and-hover; the Blaze AV already taught us the hover-lock problem |
| New VO for anyone | **Impossible** | Assemble from the library, or write it as text |
| New cutscenes | **Out of scope** | Different order of difficulty; not worth it here |

**Biggest risk:** not any single system — it's that this is roughly as much *writing* as the
entire existing mod, and the writing has to survive being assembled from a fixed pool of Jackie
takes. Mitigation: draft every beat against `vo_library/jackie.csv` *first*, and let the available
lines shape the scene rather than writing the scene and hunting for a take that doesn't exist.

**Second risk:** it must not fire before the player is ready, and must never spoil. The
questline's own history is the lesson — v1.56 shipped a gate that spoiled Jackie's survival to
pre-heist players, and v1.64 shipped one that silently never fired for anybody. Every arm
condition gates on **a fact we have positively confirmed**, defaults to silence, and ships with a
manual start button.

---

## 5. Suggested build order

1. **Spike the SMS path** (Lua or redscript shim?) — it's the one real unknown, and three parts
   depend on it. One text message from Jackie, delivered on a fact, is the whole test.
2. **Ship one real journal objective** for the *existing* retrieval quest, replacing a message-band
   flash. Proves the whole archive→journal→`ChangeEntryState` chain on something already working
   and already tested, at zero story risk.
3. **Part 1 end-to-end**, as the vertical slice: episode → SMS → objective → shard → choice.
   If Part 1 feels like a real quest, the rest is more of the same. If it doesn't, we learn it
   after one part instead of five.
4. **Part 2's heat system**, because it is what turns "he's traceable" from exposition into play.
5. Parts 3–5, writing-led.
