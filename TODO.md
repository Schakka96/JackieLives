# TODO — Jackie Lives mod

_Update after every major change. See `docs/DESIGN.md` for rationale, `docs/SETUP.md` for install steps._

## SESSION 2 (parallel edit, 2026-06-16) — MERGED into live `mod/JackieLives/`
> Session 2 staged its edits in a throwaway `working_copy_session2/`, then merged the cleanup +
> captured coords surgically into the live files (which the main session had advanced to v0.26 with
> new ISOLATED-UI-TEST picker styles). Working copy deleted after merge.

- [x] **CET window cleanup (MERGED).** Removed confirmed-done test/debug buttons from the "Jackie
      Lives" ImGui window: *Run diagnostics*, the whole *Native choice BOX experiment* block (Probe
      API / Test show box / Hide box + look-box checkbox), the *Audioware PIPE TEST* button, and the
      whole *Jackie voice* block (dropdown + Play on Jackie/Random + Play-on-V debug + Play typed
      event). **KEPT the ISOLATED UI TESTS block** (Antonia is actively iterating picker styles
      V1/V2/V3 there). Kept: Summon/Dismiss, Force main-quest, Capture position, Dialogue buttons,
      Enable schedule. (Orphaned helpers `probeChoiceBoxAPI` / `audiowareProbe` / `playVO` /
      `playRandomJackieEvent` left defined — harmless.)
- [x] **Captured schedule positions** (Antonia walked them in-game). Durable record:
      **`docs/captured_positions.md`**. Also applied to `working_copy_session2/config.lua`:
      - `misty` = Misty's Esoterica `{ -1541.072, 1195.238, 15.869 }` yaw 50.9 — **replaces Vik/Vic** as a destination.
      - `noodle` = Noodle bar `{ -1441.064, 1257.748, 23.090 }` yaw -87.1 — has a **chair** (`sitNearest = true`).
- [ ] **Give `misty` a schedule slot** in `Config.schedule` (currently captured but not placed in
      the daily timeline — noodle/coyote/afterlife/asleep already fill 24h). Decide which block Misty's takes.
- [ ] **Chair-sit at the noodle bar.** On idle-spawn at a location with `sitNearest = true`, find the
      nearest seat workspot and make Jackie sit. Feasibility: AMM can pose/sit NPCs and Codeware exposes
      the workspot system; the hard part is locating the nearest *seat* entity reliably. Approach to try:
      `Game.GetSpatialQueriesSystem()` / target nearby `Devices`/`furniture` or scan for a chair record
      near `loc.pos`, then drive the sit via AMM's animation/pose API. Needs in-game testing — not built blind.
- [ ] **Idle Jackie must not be a follower** at scheduled spots. ALREADY satisfied: `scheduleTick`
      spawns with the passive flag (`ammSpawn(0)`). Confirm visually after merge.
- [ ] **Follow-on-dialogue:** "go a job" / "let's hang out" choices flip idle Jackie → companion.
      Hook into the existing `Branch`/`summonJackie` companion path. Not built.
- [ ] **Dismiss dialogue:** a conversation option that sends companion Jackie back to idle/schedule
      (reuse `dismissJackie`, but keep him in the schedule rather than fully despawning). Not built.

## v0.24 (DEPLOYED, awaiting test) — feedback pass after v0.23 in-game test
v0.23 results: audio plays (quality poor -> WolvenKit HQ next); branching works after binding a cycle key,
Jackie responds. Issues fixed/changed in v0.24:
- [x] **Choice box = custom ImGui box** (was the native hub, which rendered choices side-by-side as F/R/1
      input prompts). Now a styled floating box: speaker name on top, choices in a VERTICAL column,
      highlighted row in YELLOW (matches docs/dialogue_picker_design.png). Drawn during gameplay.
- [x] **Removed number/Choice2-3 selection** (R/1 were bound elsewhere, didn't work). Selection is now ONLY:
      cycle key (bound to "-") moves highlight + F selects. Box shows a hint "[ - ] next  [ F ] select"
      (Config.dialogue.cycleHint). NOTE: CET can't hard-set a default binding in code; "-" is just the hint
      label - Antonia binds "Jackie dialogue: next choice" herself (she used "-").
- [x] **V's chosen line now shows as a subtitle for ~1s before Jackie replies** (Branch.confirm -> pendingAt).
- [~] **Subtitles STILL in the blue notification field, not the bottom band.** v0.22's `UIGameData.ShowDialogLine`
      push is failing -> falls back to the on-screen msg. v0.24 adds an ERROR LOG ("SUBTITLE push FAILED ...
      Error: ...") so Antonia's next test reveals the exact cause; fix definitively after. Mechanism is
      confirmed correct (Audioware uses it in Codeware.reds) - it's a CET construction detail.
- [ ] **WolvenKit HQ audio (NEXT, Antonia will install + I drive the batch).** Replace the re-encoded
      website .ogg with the game's own VO (extract .wem from opuspaks via WolvenKit -> wav; drop into the
      Audioware bank under the SAME jl_<string_id> names = manifest needs no change). lines.json has every
      vo_wem path. Step list given in chat.

## CONVERSATION BUILD — 4-step plan (Antonia, 2026-06-16, mod at v0.19)
Box rendering CONFIRMED. Now: from box -> linear conversation, step by step (each needs an in-game test).
- [~] **Step 1 (v0.19, DEPLOYED - awaiting test): make "[F] Talk" box PERMANENT.** Flipped
      `config.talk.useChoiceBox = true` so the box is now look-driven (shows when looking at Jackie in
      range, hides on look-away) instead of the one-shot "Test show box" button. Added `config.talk.boxRefresh`
      (re-assert heartbeat, 1.0s) so it survives if the game clears the blackboard while looking.
- [ ] **Step 2: pressing F LAUNCHES the dialogue box** (integrated system + blackboard; one option only,
      no conversation logic yet). The look-prompt vs the F-launched box are two states.
- [x] **Step 1 CONFIRMED in-game (v0.19): box persistent + grunt on F. Perfect.**
- [x] **Audioware PIPE CONFIRMED (v0.21): beep test plays; ver 1.9.2; manifest loads.** ROOT CAUSE of the
      earlier silence: the scraped `.ogg` are **OPUS** codec, which Audioware (kira/Symphonia) can't decode,
      so the manifest registered 0 ids ("Registry error: not found"). Fixed by converting to Ogg Vorbis.
- [~] **Steps 2-4 BUILT & DEPLOYED (v0.23) - AWAITING ANTONIA'S TEST.** All four pieces below shipped:
  - **(A) Subtitles -> real bottom band.** Was rendering in the blue notification field (SimpleScreenMessage).
        Now uses the NATIVE subtitle path `UIGameData.ShowDialogLine` / `HideDialogLine` (the exact route
        Audioware uses; see r6/scripts/Audioware/Codeware.reds). `showSubtitle/hideSubtitle/showDialogueText`
        in init.lua; falls back to the on-screen msg if `scnDialogLineData` can't build on this build.
  - **(B) 777 lines CONVERTED.** `tools/convert_audio.py` (uses a portable ffmpeg auto-downloaded to
        `tools/ffmpeg/`) re-encodes all 777 Opus `.ogg` -> Ogg **Vorbis** in `audioware/JackieLives/`
        (jl_<string_id>.ogg, ~24 MB) and regenerates the manifest (779 entries) + `index.json`
        (string_id -> {event,text}). `deploy.ps1` pushes the bank with `/PURGE`.
  - **(C) Fallback WAV.** `1155727714874494976.wav` ("Time we were on our way, mamita.") shipped as
        `jl_fallback.wav`, registered `jl_fallback`. Jackie lines fall back to it if their clip won't play.
  - **(D) BRANCHING dialogue box.** `Config.dialogueTree` (open -> howbeen/gig/bye). Jackie speaks a node's
        line (voice+subtitle), then a multi-choice native hub appears; choices are SILENT text (so missing V
        audio is moot). Selection: **F confirms the highlighted row** (reliable); bind "Jackie dialogue: next
        choice" (registerInput `jl_cycle_choice`) to move the highlight; Choice2/3 keys also select if the
        build fires them (every action is logged while a menu is open to discover the real CNames).
        CET window: "Play branching dialogue" + "Play test dialogue (linear)" buttons.
  - **OPEN QUESTION for the test:** does the multi-row hub render all choices, and does moving the highlight
        + F feel right? If native nav doesn't work, the bindable cycle key is the guaranteed fallback. If we
        want true native scroll-nav, that's the redscript route (deferred).

### !! FUTURE QUALITY MARKER (Antonia, 2026-06-16) !!
Replace the website-scraped `.ogg` (re-encoded Opus->Vorbis, slightly compressed) with the GAME'S OWN
FULL-QUALITY audio. Each line in `tools/voice-tagger/lines.json` carries `vo_wem` (e.g.
`base/localization/en-us/vo/jackie_q005_*.wem`) - extract those `.wem` via WolvenKit, convert (vgmstream),
and drop them into the Audioware bank under the SAME `jl_<string_id>` names (manifest already keyed that way,
so it's a file swap). Locate per line via string_id -> vo_wem. NOT NOW.

## NEXT SESSION — START HERE (handoff 2026-06-16, mod at v0.16)  [full history: docs/logbook.txt]
v0.15 F-trigger CONFIRMED working by Antonia. Recorder removed (code/window/hotkeys/config all gone).
Captured test coord saved: config.locations.test. v0.16 box probe ran -> first type guesses were WRONG;
decompiled scripts gave the REAL names; v0.17 (deployed) uses them - awaiting Antonia's box test.

### Choice-box authoritative facts (from CDPR-Modding-Documentation/Cyberpunk-Scripts, decompiled):
- The interactions UI controller (interactionsUI.script) registers a blackboard LISTENER on field
  `UIInteractions.InteractionChoiceHub`; on change -> `OnUpdateInteraction(Variant)` casts to
  `InteractionChoiceHubData` and builds the box. (It also listens to `VisualizersInfo` for the active
  world visualizer - OPEN QUESTION: is that anchor required for the box to appear?)
- `InteractionChoiceHubData` = { id:Int32, flags:EVisualizerDefinitionFlags, active:Bool, title:String,
  choices:array<InteractionChoiceData>, timeProvider }
- `InteractionChoiceData` = { inputAction:CName, rawInputKey:EInputKey, isHoldAction:Bool,
  localizedName:String, type:ChoiceTypeWrapper, data:array<Variant>, captionParts:InteractionChoiceCaption }
- v0.16 probe (her build) confirmed: blackboard fields `ActiveChoiceHubID` & `DialogChoiceHubs` exist;
  engine types `gameinteractionsvisListChoiceData` & `gameinteractionsChoiceCaption` construct, but
  `gameinteractionsChoiceHubData` does NOT (wrong name). The import-only engine wrappers are
  `DialogChoiceHubs{ choiceHubs:array<ListChoiceHubData> }` / `ListChoiceData` (the `vis` family).
- v0.17 approach: build `InteractionChoiceHubData` + push to `UIInteractions.InteractionChoiceHub`.
  If it renders -> iterate (add caption if row is blank). If not -> the box needs the visualizer anchor
  => pivot to WolvenKit NIF fixed-spot (Antonia's coord idea) or keep the working F+VO talk.
- [x] **BOX WORKS (v0.17, CONFIRMED in-game 2026-06-16).** "Test show box" renders a real native prompt
      "[F] Talk" via pushing an `InteractionChoiceHubData` to `UIInteractions.InteractionChoiceHub` - NO
      visualizer anchor needed, NO WolvenKit. v0.13's "impossible" box is solved from pure CET Lua. Pressing
      F plays the grunt (our OnAction hook), but the box's OWN choice-selection isn't routed yet - next polish
      if we keep it. The box label came through with just `localizedName` (no caption struct needed).

### BUILD NEW DIALOGUE + PHONE CALL — plan & progress (Antonia's new targets, 2026-06-16, full autonomy)
RESEARCH VERDICT: (1) NO native "play dialogue line by string ID" exists (confirmed across sources) - barks
are WWise events, dialogue lines are not, so you can't convert one to the other. Reusing his EXACT line
audio needs WolvenKit scene authoring OR **Audioware playing an audio file we ship** - and we ALREADY have
his `.ogg` for all 777 lines (scraper). So his real voice is reachable WITHOUT WolvenKit. (2) Dialogue
STRUCTURE (trees/choices/subtitles/facts) is very doable in CET - **Cyberscript** (cyberscript77, CET-based
JSON quest/dialogue engine) proves it; we build a lean Jackie-specific version instead of taking that dep.
3-PHASE PLAN:
- [x] **Phase 1 (v0.18, DEPLOYED - awaiting test): dialogue runner.** Pure CET, no WolvenKit. Scripted
      V<->Jackie exchange: each line = on-screen subtitle (speaker + text); Jackie's lines also fire a WWise
      voice event for presence. Data in `config.testDialogue` (includes "So let's do our thing."). CET window
      button "Play test dialogue" (summon Jackie first for his voice). This is the seed dialogue tool.
- [ ] **Phase 2: REAL voice.** Add Audioware (1 dependency) + a `voFile` per line -> play his exact scraped
      `.ogg` so he speaks the actual words (not a bark). Mostly Claude-drivable (we have the audio already).
      Quality is the website .ogg (slightly under the game .wem) but it's his real voice saying the line.
- [ ] **Phase 3: PHONE CALL (target 1).** Wrap a conversation as a holocall. Sub-parts:
      - Re-enable Jackie's CONTACT + VIDEO (Antonia: dead-Jackie call shows logo not video) -> hunt the
        "Jackie dead" fact/flag and override it; CET-testable (set facts, inspect contacts).
      - Arrival on the job: spawn at the edge of the rendered area + companion walk-to-V (feasible via our
        existing AMM summon at an offset position). BIKE arrival = vehicle AI + mount = hardest, DEFER.
      - Response line "So let's do our thing." (ID 1762127358882361344) plays via Phase-2 audio.
      - Frameworks seen: "Phone Extension" (text msgs only), "Holocalls to Audiocalls", Cyberscript phone
        conversations (text-style). None turnkey for a VO holocall -> likely our own thin layer + Audioware.
State: voice playback WORKS (Route A, his `ono_jackie_*` events; `ono_jackie_greet` confirmed on Jackie).
Talk = look at Jackie within 4 m -> weighted grunt, NATIVE on-screen message prompt "Talk to Jackie [F]".
**v0.15 (NEW, awaiting Antonia's test): real `F` trigger with NO binding** — instead of binding F (CET
can't, game reserves it), we `Observe('PlayerPuppet','OnAction')` and react when the game's own Interact
key is pressed while looking at Jackie. "=" CET fallback still bound. If F doesn't fire: set
`config.talk.logActions = true`, press F near Jackie, paste the `[JackieLives] OnAction:` lines (gives the
exact action CName) -> add it to `INTERACT_ACTIONS` in init.lua. These are the next builds:

- [~] **(TOP) Route (b): real "Talk" BOX — v0.16 ships a SAFE CET-Lua PROBE first (awaiting test).**
      RESEARCH VERDICT (2026-06-16): no public mod renders a script-pushed choice box — every "talk to NPC"
      mod (Talk to Me, Responsive NPCs, the AI ones) uses input+VO (WE HAVE THIS) or the phone UI. The
      reliable real box = **Native Interactions Framework**, but that's a WolvenKit ASSET workflow (projects/
      props/world placement), best at a FIXED spot — heavy, GUI-bound, not cleanly Claude-drivable. The one
      untried cheap path: push a `gameinteractionsChoiceHubData` to the **UIInteractions blackboard** and let
      the game's own UI controller render it (CET can set blackboard variants; this is data-push, NOT the
      v0.13 widget-attach that's impossible). v0.16 does this pcall-safe + a **"Probe API"** button that logs
      which interaction structs/blackboard fields really exist this build. Test: CET window -> "Probe API"
      (paste console), then "Test show box" while near Jackie. If it renders -> iterate the box. If not ->
      decide: WolvenKit NIF fixed-spot box (Antonia's coord idea, done legit) vs. keep the working F+VO talk.
      (decompiled scripts at codeberg adamsmasher/cyberpunk for exact ChoiceHubData fields if needed.)
- [ ] **Immersive SUMMON via PHONE CALL (replace the CET summon).** Call Jackie on the phone ->
      dialogue pops with options **"How are you doing?"** and **"Need some help with a job."** -> on the job
      option he **spawns nearby and walks to V (companion)** = our existing summon-as-companion path.
      - Bug to fix: when Jackie's dead, calling him shows only his **logo, not his video** in the phone UI.
        Defer; likely the "Jackie is dead" fact/flag — try disabling/overriding it so his contact + video work.
      - Response line for the job call (use once SENTENCE playback works): **"So let's do our thing."**
        String ID **1762127358882361344** (Quest · Spoken · quests q005_06b_the_chip, q005_06d_saburo_av).
      - This needs the phone/contact system (research how to add a callable contact + a choice hub) AND
        ties into the 777-sentence playback problem for his spoken responses.

## NOW (2026-06-16 cont.)  [see docs/logbook.txt for full history]
- [~] **Recorder v0.10 also caught NOTHING (2026-06-16, counter 0, jackie filter on AND off).** So the
      subtitle hook didn't fire either. We have NEVER confirmed CET `Observe` fires at all in this install.
      LOW PRIORITY NOW — the scraper catalogue already solves line *identification* (777 lines + String IDs),
      so the recorder is optional. To resume debugging we need ONE datum: the exact `Recorder hook
      registered: true/false on ...` console line (true = registered but not firing -> subtitles off / wrong
      method for v2.3; false = wrong class name). Next attempt should register at onInit + first prove
      Observe works on a known-good scripted method.
- [x] **Jackie line catalogue + audio — DONE (scraper).** `tools/voice-tagger/scrape_jackie.py` pulled
      all **777** of Jackie's lines (transcript + String ID + real `.ogg`) from the SoundDB API into the
      tagger. NOTE: those `.ogg` are for the TAGGER ONLY (auditioning lines on the phone) — NOT for in-game
      playback (we'd use her own installed full-quality audio for that).
- [~] **PLAYBACK — Route A WORKS for Jackie's VOICE EVENTS (v0.11, deployed).** Jackie has ~25 `ono_jackie_*`
      WWise events (greet, laughs, curious, efforts, pain, death...) + a few `vo_*jackie*` — his OWN events,
      so `AudioSystem:Play` sounds on him (same mechanism as the V grunt, but his bank). Added a "Jackie
      voice" dropdown + Play/Random/typed buttons; the look-at "Talk to Jackie" key now pulls from real
      event pools. List in `config.jackieEvents`. -> Antonia to confirm in-game (summon Jackie, Play on Jackie).
- [ ] **PLAYBACK (still open) — the 777 full dialogue SENTENCES.** These are dialogue String IDs, NOT WWise
      events, so AudioSystem:Play can't play them. Options: (A) native "play line by String ID" via the
      dialogue/voiceover/scene system — research (not yet found a clean call). (B) extract HER own `.wem`
      (full quality, same bytes the game uses) + play via Audioware. Decide once Route-A voice events are
      confirmed working. (Do NOT use the website .ogg for playback - those are tagger-only.)
- [ ] **VOICE-TAGGER — PAUSED (Antonia will run it in a NEW session).** Goal for that session: get it
      working **on her Android phone WITH audio**. Current blocker: opening `index.html` via `file://` can't
      `fetch` lines.json or load `audio/` -> falls back to the 5-line sample with no audio. Fix for phone:
      **Netlify Drop** (drag the whole `tools/voice-tagger` folder, incl. the local `audio/` — it's
      gitignored but present after running the scraper -> public https URL that works on Android with audio).
      Audio is confirmed working when SERVED (verified locally); the only issue is delivery to the phone.
- [ ] Antonia: capture coords (noodle MB8 / El Coyote Cojo / Afterlife) -> config.locations -> schedule
      then places idle Jackie at his spots.
- [ ] Later: real main-quest detection; single-instance enforcement; retrieval quest (Tier 2).

## Confirmed setup facts
- Platform: **Steam**. Build: **Patch 2.3 / 2.31** (Oct 2025). Core mod stack supports it.
- Mod manager: **Vortex**. Installed versions: RED4ext 1.30.0, redscript 0.5.31, CET 1.37.1,
  TweakXL 1.11.3, ArchiveXL 1.26.8, Codeware 1.20.3, AMM 2.12.5.
- Mod dev: source in `mod/JackieLives/`, deploy with `deploy.ps1` (auto-finds Steam install). Fast loop:
  deploy → CET overlay "Reload all mods" → load save (no exe restart needed).
- **Jackie's spawn record = `Character.Jackie`** (pinned in `config.jackieRecord`).
- Game-hour read works via the v0.3 method probe; schedule shows correct state (confirmed hour 4 = asleep).

## Setup (Tier 0 — environment)  → details in docs/SETUP.md
- [ ] Phase 0: stop auto-updates, back up saves, make test save.
- [ ] Phase 1: Vortex + Nexus account, manage Cyberpunk 2077.
- [ ] Phase 2: RED4ext → redscript → CET → TweakXL → ArchiveXL → Codeware (+ Mod Settings, Input Loader).
- [ ] Phase 3: AppearanceMenuMod (AMM).
- [ ] Phase 4: verify CET overlay opens; spawn Jackie via AMM; set follow.
- [ ] Record installed mod versions in SETUP.md table.

## MVP (prove feasibility)
- [x] MVP-0: spawn Jackie in the world — CONFIRMED (companion spawn works; record `Character.Jackie`,
      pinned in config). Idle/proximity schedule mechanism works (time + state correct); just needs coords.
- [x] MVP-1: follows/fights via companion AI — CONFIRMED in-game (follows, fights alongside V, uses
      combat barks). Act-1-independent.
- [~] MVP-2: main-quest decline — UI + decline line built; real detection still stubbed (test toggle).
- [ ] MVP-3: "Jackie returned" persistent flag (not started; schedule currently always-on).

## Immediate future (summon works — these are next up)
- **Talk to Jackie (native interact input + random VO)** — corrected goal: focus on Jackie and press the
  game's *interact key* → he plays a random line (chance + cooldown), pulling from the "conversation" /
  "greetings" pools. Pairs with the tagger "conversation" category (added).
  Reality-check / plan:
    - A *fully native dialogue-choice hub* (like vendors/quest NPCs) is heavy (scene + interaction
      system) → **defer**. Achievable now: a focus+interact trigger — same idea as the "Responsive NPCs"
      / "Talk to Me" mods (reference/reuse), scoped to Jackie + our line pool.
    - **Linchpin = playing his VO on demand.** Two routes:
        - Route A (light): trigger his *existing* in-game VO by id natively — no audio extraction. Prove first.
        - Route B (reliable): play extracted `.wem` clips via **Audioware** (new dependency) — needs the
          sounddb → WolvenKit extract → convert pipeline.
    - **Step 1 = playback proof:** make Jackie say one line on a keypress; that decides Route A vs B.
- Capture coords (noodle / coyote / afterlife) so the schedule actually places idle Jackie at his spots.
- Bike/vehicle arrival for the summon (Jackie rides up + dismounts) — DESIGN §10.1.
- Pin idle Jackie to the exact prop spot (not just "near you") — needs a placement test.
- Real main-quest detection (replace the "Force" test toggle): read tracked quest type / build blocklist.
- ~~Voice pipeline: script `lines.json` from sounddb; extract + convert `.wem → .ogg`.~~ DONE via
  `scrape_jackie.py` (777 lines + `.ogg` from the SoundDB API; no WolvenKit needed).
- Window/overlay hide polish.

## Built this session (mod v0.1 → v0.2)
- `mod/JackieLives/` CET mod: Summon companion, Dismiss, daily schedule (instant spawn by proximity),
  position-capture tool, main-quest decline (test toggle), ImGui control window + hotkeys.
- `deploy.ps1`: one-command deploy to the CET mods folder (auto-detects Steam library).
- `tools/voice-tagger/`: phone-friendly web app to audition + tag voice lines (category/mood/triggers/
  chance/locations/notes), import lines.json / export tags.

## Tier 1 — Framework & functionality
- [ ] Persistent living-NPC presence (start: instant spawn at current scheduled location when V arrives).
- [ ] `JackieCurrentState` schedule state machine (locations + Sleeping/Unavailable).
- [ ] Summon-on-side-job layer (own thin layer over companion AI / Codeware / AMM API).
- [ ] Hard main-quest ban (JournalManager quest-type check + blocklist fallback).
- [ ] "Jackie returned" state flag (persists across saves).
- [ ] Sane mod file structure + dependency list documented.

## Tier 2 — Immersion
- [ ] Retrieval questline (gated on "send Jackie to Vik" choice): rumor → Vik info shard → investigate →
      extraction → settle into the Heywood bar.
- [ ] Vik info shard / message (add, don't rewrite his scene).
- [ ] **Remove mourning content** for Mama Welles, Vik, Misty (targeted scene/quest suppression — NOT just
      a flag; see DESIGN §10.3). Verify whether "Heroes"/ofrenda is gated on body choice.
- [ ] Voice-line system: learn the game's existing bark/scene/VO trigger system; extend it to Jackie's new
      locations/states. Categories: greetings, environmental, combat, idle, emotional, banter, romance.
- [ ] Voice-line cataloguing: pull from sounddb.redmodding.org; tag moments/triggers/mood/probability.
- [ ] **Supporting tool (Claude builds):** phone-friendly local web app to audition + tag voice lines.
- [ ] "Where is Jackie" realistic-movement sub-project: travel time + cool-off between locations; bike
      arrival instead of pop-in. (Most ambitious system — stage last.)
- [ ] Mama Welles' house interior added to an empty Heywood building (advanced; defer within Tier 2).
- [ ] Jackie's bike return (easiest: suppress the gift/package texts; or SMS + inventory handover).
- [ ] Conditional greetings + barks reacting to V's story progress; pour-a-drink interaction.
- [ ] Scarcity behavior: can ignore calls / reply to texts late.
- [ ] **Single-instance enforcement** (Antonia, 2026-06-16): never allow >1 Jackie. v0.7 adds robust
      dismiss + a "Dismiss ALL" cleanup as interim; proper version = summon despawns any existing Jackie
      first, and on mod load/reload reconcile with `AMM.Spawn.spawnedNPCs` so reloads don't orphan one.

## Tier 3 — Details & fun
- [ ] Data-driven dialogue system for the ~1000-message V↔Jackie conversations.
- [ ] Small community-fixer side gigs in Heywood.
- [ ] Custom/AI voice line for V's "not dragging you into this" main-quest decline.
- [ ] Remove Jackie's drink/memory option with the Afterlife bartender.
- [ ] Scattered Jackie mentions in other NPCs (Takemura etc.) — hard, low priority.
- [ ] Romance sub-mod (separate, built on the relationship-sim layer).
- [ ] Polish pass.

## Open decisions
- Retrieval-quest trigger timing (post-Act-1 vs later).
- How aggressively to suppress mourning scenes vs. risk of quest breakage.
- Whether "Heroes"/ofrenda fires regardless of body choice (needs in-game verification).

## Problems & Resolutions (log)
- **Audioware silent, manifest registered 0 ids (2026-06-16) - RESOLVED.** `Play`/`Duration` did nothing,
  log said "Registry error: not found" and "a total of: 0 id(s)". ROOT CAUSE: the scraped `.ogg` are **Opus**
  codec (header `OpusHead`); Audioware's backend (kira/Symphonia) decodes Ogg-**Vorbis**/WAV/MP3/FLAC, NOT
  Opus, so every entry was rejected. Proven by a stdlib-generated `test_tone.wav` registering + beeping.
  FIX: `tools/convert_audio.py` re-encodes all 777 Opus->Vorbis via a portable ffmpeg (`tools/ffmpeg/`).
  LESSON: ".ogg" is a container; check the CODEC (`head -c 32 file | xxd` -> OpusHead vs vorbis).
- **`goto` is a reserved word in LuaJIT (2026-06-16) - RESOLVED before test.** The branch tree used
  `{ ..., goto = "node" }` and `c.goto`; LuaJIT (CET's runtime) reserves `goto` (Lua 5.2 statement), so this
  would be a SYNTAX ERROR failing the whole mod load. Renamed the field to `to`.
- **Subtitles showed in the blue notification field, not the bottom band (2026-06-16) - FIX deployed.**
  We used `SimpleScreenMessage` -> `UI_Notifications.OnscreenMessage` (objective-style). Real subtitles use
  `UIGameData.ShowDialogLine` (push a `scnDialogLineData`) + `HideDialogLine` - the path Audioware itself
  uses (Codeware.reds/Callback.reds). Switched to it (pcall-guarded, falls back to the old msg).
- **Jackie Lives window always on screen / didn't close with the overlay (2026-06-16).** CET calls
  `onDraw` every frame regardless of overlay state (HUD mods rely on this), so the window was effectively
  always-on. **Resolved (v0.5):** track `onOverlayOpen`/`onOverlayClose` and only draw while the overlay
  is open — the standard pattern AMM uses. Window now appears with the overlay and hides with it.
- **"Jackie record not found" — RESOLVED (2026-06-16).** `AMM.API.GetAMMCharacters()` returns only AMM's
  **19 custom** characters, NOT the base-game roster; Jackie lives in AMM's separate SQLite DB. Fixed by
  discovering his record at runtime from `AMM.Spawn.spawnedNPCs` (v0.3 "Find Jackie" button). Discovered
  record = **`Character.Jackie`**, now pinned in `config.jackieRecord` → summon works with no AMM menu.
- **`Game hour: ?` — RESOLVED (2026-06-16).** `GameTime:GetHour()` returns nil in this version; v0.3's
  multi-method probe finds the working one, so the hour reads correctly (confirmed: hour 4 → "asleep").
- **AMM has no public spawn API.** Its official `AMM.API` (Collabs/API.lua) only exposes appearance +
  character-list functions — no spawn/companion. **Resolution:** reach AMM's internal `Spawn` module via
  `GetMod("AppearanceMenuMod")` and call `Spawn:NewSpawn` → `SpawnNPC` (+ `SetNPCAsCompanion`), using the
  public `API.GetAMMCharacters()` only to look up Jackie's record. Risk: internal API may shift across AMM
  versions — pinned to AMM 2.12.5; revisit if AMM updates.
- **AMM basic spawn is passive (Antonia saw: follows, no combat/voice).** Companion mode + friendly
  attitude is what enables follow/fight/barks. **Resolution:** spawn with companion flag + hedge by
  forcing `SetNPCAsCompanion` and friendly attitude once the puppet handle resolves.
- **Can't test Lua outside the game.** **Resolution:** defensive `pcall` + `[JackieLives]` console
  logging everywhere, so failures are visible and reportable rather than silent crashes.
- **`deploy.ps1` blocked while game running (2026-06-16).** It did `Remove-Item -Recurse` first, which the
  running game/CET blocks (locked folder/handle). **Resolved (v0.6):** switched to `robocopy` overwrite in
  place (no delete) with brief retry — should now work even with the game open; clear error if a file is
  truly locked. Removed the over-promised "Reload all mods" guidance.
- **VO test silent, no errors (2026-06-16).** `AudioEvent/SoundPlayEvent + QueueEvent` and
  `GameObject.PlaySoundEvent` all ran but produced no sound on Jackie. **Fix attempt (v0.6):** use
  `Game.GetAudioSystem():Play(event, entityID, emitter)` (the call working dialogue mods use), plus a
  "play on V" toggle to separate *method-wrong* from *event-not-in-Jackie's-bank* (`ono_v_effort_short`
  is V's grunt). Pending retest + whether SoundDB exposes event ids.
- **deploy.ps1 parse error (2026-06-16).** An em-dash (non-ASCII) in a Write-Host string broke Windows
  PowerShell 5.1's parser (reads file as ANSI). **Resolved:** rewrote the script ASCII-only. Lesson: keep
  .ps1 files pure ASCII.
- **Dismiss Jackie did nothing / multiple Jackies (2026-06-16).** Despawn relied on AMM's `DespawnNPC`
  alone, which silently failed, so dismiss left the NPC in-world; each failed dismiss + new summon stacked
  orphans. **Resolved (v0.7):** robust despawn (AMM -> DynamicEntitySystem `DeleteEntity` -> dispose) +
  a "Dismiss ALL Jackies" cleanup button that sweeps `AMM.Spawn.spawnedNPCs`.
- **Voice recorder caught nothing (2026-06-16) - RESOLVED (v0.10).** ROOT CAUSE: CET `Observe` only fires
  when a *script* calls a function; Jackie's barks are triggered by the game's native C++ code, which never
  goes through the script-side stub of `AudioSystem:Play`, so the hook could never see them (confirmed: 0
  events even unfiltered). FIX: hook the SCRIPTED subtitle controller instead -
  `Observe('SubtitlesGameController','OnHideLine', fn(self,lineData))` - which the game DOES call per
  displayed line (proven by shipping subtitle mods). v0.10 reads `lineData.text/.speakerName/.id`, filters
  to Jackie by speaker, dedupes by String ID, and "Dump to file" writes `recorded_lines.json`. Requires
  subtitles ON. Awaiting Antonia's in-game test.
- **"SoundDB is catalogue-only, audio needs WolvenKit" - WRONG, audio IS downloadable (2026-06-16).** The
  SoundDB frontend plays `.ogg` previews from `https://static.zhincore.eu/cp/vo/<wem>.ogg` (public, returns
  `200 audio/ogg`). Its API (`https://sounddb.zhincore.eu/v1`, OpenAPI at `/api.json`) supports
  `q=actor:Jackie` (777 unique lines; `per_page` caps at 200; `totalCount`=977 counts gender-variant hits).
  `scrape_jackie.py` pages the API + downloads the `.ogg`, killing the WolvenKit-extraction subtask for
  tagging AND making Route-B playback far easier than planned.

## Done
- [x] 2026-06-15 — Kickoff: Option-B design, quiet-life/living-NPC architecture, tier plan, MVP defined.
      Scaffolding (CLAUDE.md, DESIGN.md, TODO.md).
- [x] 2026-06-15 — Confirmed Steam + Patch 2.3/2.31; core mod stack compatible. Chose Vortex. Wrote
      SETUP.md. Folded detail_ideas.txt into DESIGN.md §10 with reality-checks.
- [x] 2026-06-16 — Setup complete (Vortex + stack + AMM; Jackie spawns/follows verified). Built mod v0.1
      (summon companion + schedule + decline + capture), deploy.ps1, and the voice-tagger web app.
- [x] 2026-06-16 — **MVP CONFIRMED in-game (mod v0.3):** Jackie summons, follows, fights alongside V with
      combat barks. Record `Character.Jackie` pinned. Time/schedule state correct (hour 4 = asleep).
      Decline flow built (test toggle). Tagger gained a "conversation" category.
- [~] 2026-06-16 — **v0.4 VO playback experiment** shipped: 3 buttons (AudioEvent / SoundPlayEvent /
      PlaySoundEvent helper) play `Config.talkTest.event` on Jackie. Route A proof. Audioware approved as
      fallback (Route B) if native VO won't play his lines. Awaiting in-game test result.
- [x] 2026-06-16 — **v0.7/v0.8:** fixed deploy.ps1 (ASCII), robust dismiss + "Dismiss ALL" cleanup,
      switched VO to `AudioSystem:Play` (plays on V! method confirmed). Built a **voice recorder** (v0.8)
      that hooks `AudioSystem:Play` and logs the event names firing on Jackie's entity.
      KEY INSIGHT: `AudioSystem:Play` needs **WWise event names** (`eventsmetadata.json`), which are
      DIFFERENT from SoundDB's String IDs / `.wem` paths — that's why his lines weren't findable in the DB.
      Open question: do his scripted dialogue lines even have standalone events (barks/efforts do; deep
      dialogue may need extraction + Audioware = Route B).
- [x] 2026-06-16 — **v0.5: window visibility fixed** (overlay-gated draw). **Talk-to-Jackie trigger built:**
      bindable "Talk to Jackie" key + look-at detection + random line from `Config.talkLines` with
      chance/cooldown (greeting vs conversation pool). Audible result pending the VO route + real event ids.
      Fully native dialogue-choice prompt intentionally deferred (heavy). Awaiting coords from Antonia.
- [x] 2026-06-16 02:36 — **v0.9:** removed unused CET-window buttons (Hide window / Dismiss ALL / Find
      Jackie) per Antonia. Wrote docs/logbook.txt (full chronological history). Session paused for the night.
- [x] 2026-06-16 (day) — **Recorder root-caused & rebuilt (v0.10)** as a subtitle-controller hook
      (`SubtitlesGameController:OnHideLine`) + "Dump to file"; deployed. **Built `scrape_jackie.py`** and
      pulled all 777 Jackie lines + `.ogg` audio from the SoundDB API into the tagger (verified: tagger
      shows 777, audio plays, context/quest hints + metadata preserved). Lifted the tagger waitlist.
- [x] 2026-06-16 (day) — Recorder v0.10 TESTED -> 0 (subtitles were on, lines visible). Recorder SHELVED
      (catalogue already identifies lines). **v0.11: working "Jackie voice" playback** — discovered his ~25
      `ono_jackie_*` + `vo_*jackie*` WWise events in SoundDB; added a dropdown + Play/Random/typed buttons
      and wired the Talk-to-Jackie key to real event pools. **CONFIRMED in-game: `ono_jackie_greet` plays
      on Jackie** (Route A works).
- [x] 2026-06-16 (day) — **v0.12: immersive talk** — look at Jackie + bound key (no overlay) -> weighted
      random grunt: 95% common (greet/curious/phone), 5% rare (bump/additional/laughs_soft). In
      `config.talk` + `config.talkLines`. Deployed.
- [x] 2026-06-16 (day) — **v0.13 ink box FAILED:** `gameuiHUDGameController` is NATIVE in patch 2.3 — it
      has no scriptable `OnInitialize` (CET threw "Function OnInitialize ... does not exist"), and the
      `inkHUDGameController` base is per-MODULE, not the HUD root. So CET Lua can't attach a custom widget
      to the HUD root here. **v0.14:** dropped the ink box; the Talk prompt now uses the game's NATIVE
      on-screen message system (`UI_Notifications.OnscreenMessage` via blackboard — reliable, no attach):
      look at Jackie nearby -> "Talk to Jackie [<key>]" appears -> press key -> grunt. Key label is
      configurable (`config.talk.keyLabel`, default "=" since CET won't bind F). Deployed. **CONFIRMED:
      message prompt shows (blue text) when looking at Jackie; "=" plays the grunt.**
- [ ] **Literal yellow-band dialogue box — still open.** Routes: (a) NIF/World Builder real box at Jackie's
      FIXED spot (needs coords + WolvenKit); (b) a small REDSCRIPT module to hook the native HUD/interaction
      (redscript can wrap native methods Lua can't) — more work, can attempt. CET-Lua alone can't do it in 2.3.
- [x] **CET can't bind F — SOLVED a different way (v0.15, awaiting in-game confirm).** Don't *bind* F;
      *observe* the game's own interact handler. `Observe('PlayerPuppet','OnAction')` is hookable (scripted
      method), so we watch for the Interact/Choice action press and fire Talk-to-Jackie when looking at him.
      No binding, works on moving Jackie, foundation for the real box. `config.talk.logActions` debug toggle
      prints action names to confirm the exact CName if the first test doesn't fire.
- [ ] **Native "talk BOX" at a FIXED spot (Antonia asked 2026-06-16) — deferred, here's why.** The literal
      yellow-band choice box is the native interaction system. Two honest routes, neither a quick CET hack
      (a blind CET-Lua choice-hub push is the same trap that killed v0.13's ink box): (a) **WolvenKit /
      ArchiveXL world-builder** = author a prop+interaction `.archive` placed at world coords — legit but
      GUI-heavy and not smoothly Claude-drivable for a beginner throwaway; (b) **redscript module on Jackie**
      = render a real `gameinteractionsChoiceHubData` from the same module that now catches F (TOP item).
      Recommend (b): one module gives the moving box AND F together. Need to verify the exact 2.3 ChoiceHub
      API before shipping (no blind guess). Captured test coords saved in `config.locations.test`
      (`{-854.737, 1833.329, 36.207}`, yaw 44.4).
