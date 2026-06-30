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

**Bring Jackie along on a gig.** Two ways:
- **Call him** — phone Jackie's number; he takes the holocall and arrives to meet you.
- **Find him in the world** — Jackie keeps a daily routine around his Heywood haunts (El Coyote
  Cojo, Lizzie's Bar, the Afterlife, the noodle bar, Ginger Panda, Redwood Market, Misty's
  Esoterica — which one depends on the time of day). Walk up and ask him to tag along.

Either way he arrives from a distance and walks up — he never just pops in next to you — then
follows and **fights at your side**. He'll come along on **side jobs only**: ask during a **main
quest** and V refuses to drag him into it.

**Dismiss Jackie.** Either tell him in conversation that you'll **head on alone**, or use the
**Go Home Jackie** button in the mod settings menu (also the recovery option if he ever gets stuck).

**Settings menu** — Esc → Settings → **Jackie Lives** (via Native Settings UI):
- **Go Home Jackie** — send him home / full reset if anything goes wrong.
- **Disable vehicle arrivals** — his bike arrival is a little less stable; turn this on and he'll
  always arrive **on foot** instead.
- Toggles persist across saves.

**Talk to Jackie** — bind a key in CET's **Bindings** tab, then look at him and press it; he
responds with a line (shown as a subtitle in this mute version).

> Tip: open the CET overlay (default **`~`**) for the **Jackie Lives** debug window — extra summon/
> arrival buttons and a status readout, handy if something misbehaves.

## Troubleshooting

Open the CET overlay; the console shows lines starting with `[JackieLives]`.
- *"AMM Spawn module not available"* → AppearanceMenuMod isn't installed/loaded.
- Settings page missing → check the `nativeSettings` folder name (see Requirements).

## Credits & notice

Fan-made mod for **Cyberpunk 2077**. Not affiliated with or endorsed by CD PROJEKT RED. All game
content remains the property of CD PROJEKT RED. Requires a legally owned copy of the game.
