# Story-NPC presence gate — Jackie excuses himself near major NPCs (TODO feature #3b)

_Created 2026-07-03 from Antonia's full character list. Reference data + design for the proximity gate._

## Design
When a companion Jackie is tagging along and V approaches a **dialogue-heavy story NPC** within
**~50 m** (tunable, `Config.presence.radius`), Jackie **says goodbye** — a short "got some biz to attend
to, catch you later" line — and walks off (reuse `startLeaving`, same as the main-quest excuse). He does NOT
bail during ordinary free-roam or around ambient/neutral NPCs. This layers on top of:

### Designated goodbye line (Antonia 2026-07-06)
Jackie's walk-away line here is **"Ahí luego, V."** — the same line now wired as the parting-line pool for
the dismiss/send-away flow (`Config.dismiss.partingPool`). At least **3 clean in-game instances** exist.
The presence gate calls the same `startLeaving`, so once the VO is scraped into the Audioware bank and its
`jl_<decimal>` id lands in `partingPool`, this gate speaks it for free — no extra wiring. See
`docs/VOICE_LINES.md` → "Bye". Until the clip is in the bank the pool entry runs `sfx=nil` (text+grunt fallback).

This layers on top of:
- **(3a) cutscene gate** — leave when a scripted scene/cinematic tier starts, and
- **(3c) main-quest gate** — the existing `isMainQuestActive()` ban (v0.62). ✅ **CONFIRMED working
  in-game (Antonia 2026-07-06):** during a real main quest Jackie says bye and walks off. The presence
  gate (3b) reuses this same say-bye-and-leave path.

Together they stop Jackie loitering in scripted Judy/Panam/Peralez/Hanako scenes.

### Rule = allowlist, not blocklist
The **default for every story NPC below is LEAVE.** Only an explicit **STAY allowlist** keeps him around.
That's simpler and safer than perfectly classifying ~80 names, and matches Antonia's note ("some are fine").

**STAY allowlist (Jackie is fine near these — do NOT trigger the goodbye):**
| Character | Why he stays |
|-----------|--------------|
| **Viktor Vektor** | In on the secret; friend. |
| **Mama Welles** | His mother; part of his story. |
| **Misty Olszewski** | Friend; in on it. |
| **Delamain** | It's the AI cab — no real co-presence. |
| Johnny Silverhand | In V's head — never a world-proximity NPC (N/A anyway). |
| Jackie Welles | Himself. |

### Implementation notes
- **Needs a TweakDB character record ID per LEAVE npc** for the runtime nearby-NPC scan. Harvest these from
  **AMM's own character database** (the mod already uses AMM + `getAMMCharacters`) or the spawn-codes wiki —
  AMM knows all these NPCs, so we lift the record IDs from there rather than guessing. `- [ ] RESEARCH: fill
  the Record ID column.`
- Scan nearby NPCs each tick (reuse the existing target/`getAMMCharacters` enumeration), test record ID ∈
  LEAVE-set, respect a cooldown so he doesn't re-trigger, and skip if already leaving/in a scene.
- **200-local cap:** build as globals or a new `presence.lua` module — never new top-level `local`s in init.lua.
- Many story NPCs only appear inside main-quest cutscenes → the **cutscene + main-quest gates already cover
  them**; the proximity gate mainly matters for NPCs met in **side/free-roam** content where Jackie can be
  summoned (Judy, Panam, River, Kerry, Peralezes, Mitch, PL Dogtown NPCs, etc.). "Already covered" ones are
  marked so we don't spend effort on their record IDs first.

---

## Full character list (disposition = best-effort default — **Antonia, please eyeball**)
Disposition key: **STAY** = allowlist above · **LEAVE** = trigger the goodbye near this NPC ·
**N/A** = not a world-proximity NPC for a free-roam companion (dead pre-revival / in V's head / net entity /
main-quest-boss-only, already covered by the cutscene + main-quest gates). Record ID = TBD (harvest from AMM).

### Base Game
| Character | Disposition | Notes / where encountered | Record ID |
|-----------|-------------|---------------------------|-----------|
| V | N/A | The player. | — |
| Adam Smasher | N/A | Boss, main-quest only. | |
| Anders Hellman | LEAVE | Named by Antonia. Main quest + one side scene. | |
| Anthony Harris | LEAVE | Peralez side arc ("I Fought the Law"). Low priority. | |
| Alt Cunningham | N/A | Net entity, no world proximity. | |
| Maman Brigitte | LEAVE | Named by Antonia. Voodoo Boys, Pacifica. | |
| Carol Emeka | LEAVE | Minor. Low priority. | |
| Chang-Hoon Nam | LEAVE | Side gig. Low priority. | |
| Claire Russell | LEAVE | Afterlife bartender + racing side quests (dialogue-heavy). | |
| Delamain | STAY | Allowlisted (AI cab). | — |
| Dexter DeShawn | N/A | Dies in Act 1; pre-revival. | |
| Elizabeth Peralez | LEAVE | Named ("Peralezes"). "Dream On" side quest. | |
| Evelyn Parker | N/A | Dies; pre-revival. | |
| Finn "Fingers" Gerstatt | LEAVE | Ripperdoc, dialogue scenes. Low priority. | |
| Goro Takemura | LEAVE | Named earlier. | |
| Hanako Arasaka | LEAVE | Named. Mostly main-quest (already covered). | |
| Jackie Welles | STAY | Himself. | — |
| Jefferson Peralez | LEAVE | Named ("Peralezes"). | |
| Johnny Silverhand | STAY/N/A | In V's head — no proximity. | — |
| Joshua Stephenson | LEAVE | "Sinnerman" side quest, very dialogue-heavy. | |
| Judy Álvarez | LEAVE | Named earlier. Side/romance arc. | |
| Kerry Eurodyne | LEAVE | Side/romance arc. | |
| Lizzy Wizzy | LEAVE | "Violence" side quest / concert. | |
| Lucius Rhyne | N/A | Mayor; minor/mentioned. | |
| Maiko Maeda | LEAVE | Clouds / Judy arc. | |
| Mama Welles | STAY | Allowlisted. | — |
| Misty Olszewski | STAY | Allowlisted. | — |
| Mitch Anderson | LEAVE | Named. Aldecaldos side content. | |
| Nix | LEAVE | Afterlife netrunner. Low priority. | |
| Oswald "Woodman" Forrest | LEAVE | Clouds. Low priority. | |
| Panam Palmer | LEAVE | Named earlier. Side arc. | |
| Placide | LEAVE | Named. Voodoo Boys. | |
| River Ward | LEAVE | Side/romance arc. | |
| Rogue Amendiares | LEAVE | Afterlife; Kerry/Johnny arc. | |
| Saburo Arasaka | N/A | Dead. | |
| Sandayu Oda | N/A | Main-quest boss. | |
| Sandra Dorsett | LEAVE | Minor side gig. Low priority. | |
| Saul Bright | LEAVE | Aldecaldos, Panam arc. | |
| Royce | N/A | Maelstrom; dies/early, pre-revival. | |
| T-Bug | N/A | Dies Act 1; pre-revival. | |
| Us Cracks — Blue Moon | LEAVE | "Us Cracks" side quest / concert. Low priority. | |
| Us Cracks — Purple Force | LEAVE | As above. | |
| Us Cracks — Red Menace | LEAVE | As above. | |
| Viktor Vektor | STAY | Allowlisted. | — |
| Weldon Holt | N/A | Councilman; minor. | |
| Yoko Tsuru | N/A | Minor. | |
| Yorinobu Arasaka | N/A | Main-quest only. | |

### Phantom Liberty
> ⚠️ The pasted PL list ran several names together — I split it best-effort. **Please eyeball the ambiguous
> rows** (flagged `?`). All PL story content is in Dogtown, so proximity matters if Jackie is ever summoned there.

| Character | Disposition | Notes | Record ID |
|-----------|-------------|-------|-----------|
| Aaron Waines | LEAVE | Minor. Low priority. | |
| Albert Murphy | LEAVE | Minor. Low priority. | |
| Alena "Alex" Xenakis | LEAVE | Major PL companion. | |
| Angelica Whelan | LEAVE | Minor. Low priority. | |
| Aurore Cassel | LEAVE | The Cassels (PL). | |
| Aymeric Cassel | LEAVE | The Cassels (PL). | |
| Barbara "Babs" Okoye | LEAVE | Heist crew. Low priority. | |
| Bree Whitney | LEAVE | Minor. Low priority. | |
| Charles Graham | LEAVE | Minor. Low priority. | |
| Chester Bennett | LEAVE | Minor. Low priority. | |
| Damir Kovac | LEAVE | Minor. Low priority. | |
| Dante Caruso | LEAVE | Minor. Low priority. | |
| Farida Nazeri | LEAVE | Minor. Low priority. | |
| Kurt Hansen | LEAVE | PL antagonist; largely main-PL (covered). | |
| "Too" / "Lina" (?) | ? | **Token unclear in paste** — please confirm who this is. | |
| Jago Szabó | LEAVE | PL. Confirm. | |
| Lina Malina | LEAVE | PL. Confirm. | |
| Paco Torres | LEAVE | PL. Confirm. | |
| Rosalind Myers | N/A | NUSA President; main-PL only. | |
| Wilky "Slider" LaGuerre | LEAVE | PL. | |
| Solomon Reed | LEAVE | Major PL character. | |
| Song So Mi "Songbird" | LEAVE | Major PL character; largely main-PL. | |
| Yuri Bychkov | LEAVE | PL. | |
