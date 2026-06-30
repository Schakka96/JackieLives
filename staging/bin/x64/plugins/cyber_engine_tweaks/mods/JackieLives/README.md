# Jackie Lives

Bring Jackie Welles back to Night City as a summonable companion and a living presence around
his old Heywood haunts. Summon him to fight at your side on side jobs — but try it during a main
quest and V will refuse to drag him into it.

> **Mute version.** This release has **no voice audio** — Jackie's lines appear as on-screen
> subtitles. (His real voice can't be redistributed for copyright reasons.) Everything else works.

## Requirements

Install these first (all from Nexus Mods):

- **Cyber Engine Tweaks (CET)** — version **1.18.1 or newer**
- **AppearanceMenuMod (AMM)** — handles Jackie's spawning and combat AI
- **Codeware**
- **Native Settings UI** — adds the in-game settings page (Esc → Settings → Jackie Lives)
  - ⚠️ Its folder **must** be named exactly `nativeSettings` inside
    `…\cyber_engine_tweaks\mods\`. If your download extracted to something like
    `CP77_nativeSettings-…`, rename the folder to `nativeSettings` or this mod's settings page
    won't appear.

## Install

**With a mod manager (Vortex / MO2):** download the zip and install it like any other mod — it
unpacks into the correct game folders automatically.

**Manually:** open the zip and copy the `bin` folder into your Cyberpunk 2077 install directory,
merging when prompted. The mod's files should end up at:
```
…\Cyberpunk 2077\bin\x64\plugins\cyber_engine_tweaks\mods\JackieLives\
```

## How to use

1. In-game, open the CET overlay (default key **`~`**). A **"Jackie Lives"** window appears.
2. **Summon Jackie** — click the button; he spawns and follows/fights on your side.
3. **Dismiss Jackie** — removes him.
4. **Talk to Jackie** — bind a key in CET's **Bindings** tab, then look at him and press it; a
   line plays as a subtitle.
5. **Settings** — Esc → Settings → **Jackie Lives** (recovery button + toggles), via Native Settings UI.

Note: summoning works immediately. His scheduled appearances at Heywood spots only activate once
locations are captured in `config.lua` (advanced/optional).

## Troubleshooting

Open the CET overlay; the console shows lines starting with `[JackieLives]`.
- *"AMM Spawn module not available"* → AppearanceMenuMod isn't installed/loaded.
- Settings page missing → check the `nativeSettings` folder name (see Requirements).

## Credits & notice

Fan-made mod for **Cyberpunk 2077**. Not affiliated with or endorsed by CD PROJEKT RED. All game
content remains the property of CD PROJEKT RED. Requires a legally owned copy of the game.
