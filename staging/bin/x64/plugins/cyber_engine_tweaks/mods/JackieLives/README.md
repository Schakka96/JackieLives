# Jackie Lives — CET prototype mod (MVP)

A Cyber Engine Tweaks mod that summons Jackie as a combat companion, declines the summon during main
quests, and gives him a simple daily schedule at his Heywood spots. Spawn + combat AI are delegated to
**AppearanceMenuMod (AMM)**; this mod owns the trigger / schedule / ban logic.

## Requirements

**Core (required — the mod won't run without these):**
- **RED4ext** — native plugin loader that Codeware and Audioware sit on.
- Cyber Engine Tweaks (**1.18.1+** — required by Native Settings UI)
- AppearanceMenuMod (AMM)
- Codeware

**For Jackie's real voice (optional, but it's the whole point):**
- **Audioware** — plays his voice lines. Without it the mod runs **subtitle-only** (no crash). CDPR's
  audio can't be redistributed, so you extract it yourself and drop it in — see
  `r6\audioware\JackieLives\HOW_TO_ADD_JACKIE_VOICES.txt`.

**For his mouth to move while he talks:**
- **AMM Expressions Overhaul** ([Nexus mod 20108](https://www.nexusmods.com/cyberpunk2077/mods/20108)) —
  provides the "Talking" facial anims the lip-flap uses. Without it he still speaks, but his lips stay still.

**For the in-game settings page:**
- **Native Settings UI** (`nativeSettings`) — adds the in-game **Esc → Settings → Jackie Lives**
  page (the "Go Home Jackie" recovery button). Get it from
  [Nexus mod 3518](https://www.nexusmods.com/cyberpunk2077/mods/3518).
  - ⚠️ **The folder MUST be named exactly `nativeSettings`** under
    `...\cyber_engine_tweaks\mods\`. `GetMod("nativeSettings")` looks it up *by folder name*; if a
    download extracts to `CP77_nativeSettings-…` or similar, the lookup returns nil, the page never
    appears, and Native Settings' own panel shows *"No mods using native settings installed!"* (that
    message means Native Settings loaded fine but no mod registered with it). Rename the folder if so.
  - ℹ️ **Load order is handled in code, not by you.** CET loads mods alphabetically, so `JackieLives`
    initializes before `nativeSettings`. Rather than register in `onInit` (where
    `GetMod("nativeSettings")` could still be nil), we retry from `onUpdate` (`nsTick`) until it's
    available, then register once. No manual load-order/priority setup is needed — just install the
    dependency. If the page still doesn't show, check the CET console for the `[JackieLives]` line:
    `…panel registered` (success), `…registration FAILED: <err>` (API error — send to Claude), or
    `…not found after retries` (the `nativeSettings` folder is missing/misnamed — see the warning above).

## Install / update (one command)
From the project root (`...\Cyberpunk_modding`), in PowerShell:

```powershell
.\deploy.ps1
```

This copies `mod\JackieLives` into the game's CET mods folder
(`...\Cyberpunk 2077\bin\x64\plugins\cyber_engine_tweaks\mods\JackieLives`). If it can't auto-find the
game, run `.\deploy.ps1 -GameDir "X:\path\to\Cyberpunk 2077"`.

**Fast iteration (no exe restart):** run `.\deploy.ps1` anytime (main menu, in-game, or alt-tabbed —
files aren't locked), then open the CET overlay and click **"Reload all mods"** (main CET window, near
the Console/Bindings tabs). Confirm it took: console prints `[JackieLives] Loaded vX`. You still need to
**load a save to test spawning** (no world at the main menu). If a hot-reload acts weird, do a full
restart to clear state.

## Use it
1. In-game, open the CET overlay (default `~`). The **"Jackie Lives"** window appears — it shows *only*
   while the overlay is open and closes with it (the "Hide window" button / toggle key hides just it).
2. **Summon Jackie (companion):** click the button → Jackie spawns and should follow + fight on your side.
3. **Dismiss Jackie:** removes the companion.
4. **Test the main-quest decline:** tick **"Force main-quest active"**, then Summon → V declines instead.
5. **Bind keys** in CET's **Bindings** tab: Summon / Dismiss / Capture / Show-Hide window / VO test, and
   **"Talk to Jackie"**.

### How he follows you
- **He walks beside you**, slightly ahead, whenever you're at a walking pace on flat ground — rather than
  trailing on a leash. Don't like it? **Esc → Settings → Jackie Lives → Gameplay → "Walk beside me"** turns
  it off and he reverts to a plain trailing follower.
- **On stairs and slopes he drops in behind you** and goes single file, then slides back to your side once
  you're on level ground again. (A staircase is rarely two abreast.)
- **When you crouch, he crouches and shadows you** a few metres back, never in front — so he stays out of
  the vision cone you're sneaking through. As a proper companion he's ignored by enemy perception anyway.
- If you get far enough ahead (a long sprint, a fast-travel), he catches up on his own.

### Talk to Jackie
Bind **"Talk to Jackie"** (CET → Bindings), then **look at Jackie and press it** → he plays a random line
(greeting after a 60s+ gap, else conversational; with a cooldown so he doesn't repeat). Tune
`Config.talk` (range / cooldown / chance) and fill `Config.talkLines` with his event ids.
- Want a native feel? You *can* bind "Talk to Jackie" to the same key you use to interact. A truly native
  dialogue-choice prompt (like vendors) is a heavier future upgrade, not this.
- Voice: with **Audioware** installed and his audio files added (see
  `r6\audioware\JackieLives\HOW_TO_ADD_JACKIE_VOICES.txt`) he speaks his real lines; without them it's
  subtitle-only. His lips move only if **AMM Expressions Overhaul** is installed.

### Call Jackie onto a gig (arrival)
Click **"Call Jackie (holocall)"** → a short call plays; ask him along and he ARRIVES from a distance and
walks up as your companion (he never just pops in next to you). Two **arrival methods**, toggled live in
the window with **"Arrival method"** (and **"Test arrival now"** fires one without a call):
- **FOOT** (default) — spawns ~50 m off to one side of you, sprints in, walks the last stretch.
- **BIKE** — spawns ~60 m back on his Arch, rides in, parks on the road ~20 m out, walks the rest.

He spawns on a valid street at *your* height (not a roof/other floor), and if he ever can't path to you
he respawns a little closer until he reaches you. Tuning lives in `Config.call` + `Config.vehicle`
(spawn distances, where he becomes a companion, bike park distance, etc. — all commented). The CET
console logs his distance every few seconds (`riding in... 44 m to V`) so you can see what he's doing.

## Relationship mode — Husbando / Hermano (v1.2)
Jackie has two dialogue tracks, set in **Esc → Settings → Jackie Lives → Relationship**:
- **Husbando** — the female-V default: he and V have a slow-burn thing, he's more flirty, and he's
  broken things off with Misty.
- **Hermano** — the male-V default (canon): he's your brother-in-arms, strictly choom, still with Misty.

It's **auto-picked from your V's body gender the first time you load in** and locked from then on (a
`genderLock` flag saved in `jl_settings.txt`); flip it anytime with the switch. It reshapes his talk /
holocall / arrival / dismiss lines, the reunion, and the Vik / Misty / Mama recovery notes. Authoring
lives in `config.lua` (`Config.hermanoLines` + inline `m = {...}` overrides) and `retrieval.lua` (the
shard texts). ⚠️ The male-V voice pool is thin (68 clips), so some Hermano lines are subtitle-only (mute)
by design; the voiced male clips are marked `⚠️ VERIFY` in `config.lua` for an in-game ear-check.

## Capture his locations (needed for the schedule)
The schedule only spawns idle Jackie at spots whose coordinates you've captured.
1. Walk to the exact spot (e.g. the noodle stand in front of MB8).
2. In the "Jackie Lives" window, click **"Capture current position"**.
3. A line like `pos = { 123.456, -78.900, 12.300 }, yaw = 90.0` is shown and printed to the CET console.
4. Paste it into the matching entry in `config.lua` (e.g. `noodle = { name = "...", pos = { ... }, yaw = ... }`).
5. Repeat for **coyote** (El Coyote Cojo) and **afterlife** (Afterlife).
6. Re-deploy (`.\deploy.ps1`) and reload mods.

Once captured, walk near a spot during its time block and Jackie appears; leave and he despawns.
Schedule: a **5-day shuffle bag** (`active1/2/3/quiet/gone` in `config.lua`), one day-type per in-game
day — all seven venues appear across the active days. He sleeps 00:00–06:00 and always winds down at El
Coyote before bed (a `gone` day = out of town, no appearances).

### Fine-tune his seats (the seat tuner)
AMM's sit animation is freestanding (invisible chair), so a captured spot rarely lands him perfectly on
a real stool/chair the first time. The **"Seat position tuner"** panel (in the Jackie Lives window) lets
you nudge a seat live until it's right:
1. In the tuner, click the **Venue** you want (only venues with a sit spot are listed) — this also sends
   Jackie there. Walk over to him.
2. Slide **X / Y / Z** (position) and **Yaw** (which way he faces) — with **Live** ticked he re-seats as
   you go. Yaw is what fixes a seat that faces the wrong way; it's now consistent no matter how he arrived.
3. If a venue has more than one stool, use **`< prev seat / next seat >`** to choose which one you're editing.
4. Click **"Print coords → config.lua"**. The line appears in the console + the "Last capture" box. Paste
   it to Claude (or into the venue's `waypoints` entry yourself) to make it permanent.

Collision note: idle Jackie's collision is dropped while he's at a venue (so chairs can't block/shove
him) — the window's **"Collision … live on Jackie"** line confirms it's off. Toggle with the
**"Idle Jackie: collisions OFF"** checkbox.

## Troubleshooting
- Open the CET overlay; the console shows lines starting with `[JackieLives]`. **Red errors → send them
  to Claude.** Common ones the status line will tell you: "AMM Spawn module not available" (AMM not
  loaded), "Jackie record not found" (AMM character DB issue).
- If Jackie spawns but doesn't follow/fight, that's the companion hedge not catching — tell Claude; it's
  a known iteration point.
- Exact placement: idle Jackie spawns when you reach his spot (within `proximityRadius`) and walks to his
  waypoint. To dial a seat onto a real stool/chair, use the **seat tuner** (see "Fine-tune his seats").

## Files
- `init.lua` — all logic (summon, schedule, ban, capture, UI, relationship-mode swap engine).
- `config.lua` — **the file you edit**: locations, schedule, ban list, decline line, dialogue trees +
  the Hermano line overrides (`Config.hermanoLines` / inline `m`).
- `retrieval.lua` — the "Where's Jackie?" retrieval questline + the Husbando/Hermano recovery-note text.
- `blaze.lua` — the optional "Blaze of Glory" story mode (the Konpeki set-piece and its finale).
- `session.lua` — session guard: detects a new game / load-from-save so stale entity handles from the
  previous session are never touched again.
