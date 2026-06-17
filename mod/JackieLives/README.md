# Jackie Lives — CET prototype mod (MVP)

A Cyber Engine Tweaks mod that summons Jackie as a combat companion, declines the summon during main
quests, and gives him a simple daily schedule at his Heywood spots. Spawn + combat AI are delegated to
**AppearanceMenuMod (AMM)**; this mod owns the trigger / schedule / ban logic.

## Requirements
- Cyber Engine Tweaks (**1.18.1+** — required by Native Settings UI)
- AppearanceMenuMod (AMM)
- Codeware
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

### Talk to Jackie
Bind **"Talk to Jackie"** (CET → Bindings), then **look at Jackie and press it** → he plays a random line
(greeting after a 60s+ gap, else conversational; with a cooldown so he doesn't repeat). Tune
`Config.talk` (range / cooldown / chance) and fill `Config.talkLines` with his event ids.
- Want a native feel? You *can* bind "Talk to Jackie" to the same key you use to interact. A truly native
  dialogue-choice prompt (like vendors) is a heavier future upgrade, not this.
- No voice yet? The pools use a placeholder event; real Jackie audio depends on the VO playback test
  (Route A native event ids vs Route B Audioware).

## Capture his locations (needed for the schedule)
The schedule only spawns idle Jackie at spots whose coordinates you've captured.
1. Walk to the exact spot (e.g. the noodle stand in front of MB8).
2. In the "Jackie Lives" window, click **"Capture current position"**.
3. A line like `pos = { 123.456, -78.900, 12.300 }, yaw = 90.0` is shown and printed to the CET console.
4. Paste it into the matching entry in `config.lua` (e.g. `noodle = { name = "...", pos = { ... }, yaw = ... }`).
5. Repeat for **coyote** (El Coyote Cojo) and **afterlife** (Afterlife).
6. Re-deploy (`.\deploy.ps1`) and reload mods.

Once captured, walk near a spot during its time block and Jackie appears; leave and he despawns.
Schedule (game-time): 08–14 noodle · 14–20 Coyote Cojo · 20–02 Afterlife · 02–08 asleep/unavailable.

## Troubleshooting
- Open the CET overlay; the console shows lines starting with `[JackieLives]`. **Red errors → send them
  to Claude.** Common ones the status line will tell you: "AMM Spawn module not available" (AMM not
  loaded), "Jackie record not found" (AMM character DB issue).
- If Jackie spawns but doesn't follow/fight, that's the companion hedge not catching — tell Claude; it's
  a known iteration point.
- Exact placement: idle Jackie currently appears *near* you when you reach his spot (within
  `proximityRadius`), not pinned to the exact prop. Precise placement is a planned follow-up.

## Files
- `init.lua` — all logic (summon, schedule, ban, capture, UI).
- `config.lua` — **the file you edit**: locations, schedule, ban list, decline line.
