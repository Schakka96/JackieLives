# Jackie Lives — v1.64.1

Brings **Jackie Welles** back after his Act 1 death, in a lore-friendly way, as a **living Night City
NPC** — not a default follower. He didn't die at Vik's: he was smuggled out and quietly healed, chose
out of the merc life, and now works a bar and does low-level fixer work in Heywood.

He's **gated behind a retrieval questline** — Vik lets slip that he's alive, you find his note in the
Badlands, and a reunion brings him home. Only then does the rest unlock: a daily schedule at his
Heywood haunts, branching voiced dialogue on **[F]**, calling him onto **side jobs** (never the main
plot), dinner outings, and a companion who walks at your side and rides along when you take a bike.

Since v1.68 the mod spawns Jackie itself, using the base game — **AppearanceMenuMod is no longer
required**. If you already run AMM and would rather keep the old behaviour, there is a switch for it:
Esc → Settings → JackieLives → Compatibility → *Use AMM for spawning*.

## Requirements

**Core (required — the mod won't run without these):**
- **RED4ext** — native plugin loader that Codeware and Audioware sit on.
- Cyber Engine Tweaks (**1.18.1+** — required by Native Settings UI)
- Codeware

**Optional:**
- **AppearanceMenuMod (AMM)** — adds the sit/lean poses at venues, and lets you switch the spawn back
  to AMM's own (Esc → Settings → JackieLives → Compatibility). Nothing breaks without it.

**For Jackie's real voice (optional, but it's the whole point):**
- **redscript** — and that's it. Jackie speaks in his actual voice, using the recordings already in
  your own copy of the game. Nothing to download, extract, convert or rename.

  *(New in v1.66. Previous versions needed Audioware plus a ~940 MB manual extraction with WolvenKit.
  If you did that, it still works and nothing is lost — the mod just doesn't need it any more.
  Without redscript he falls back to subtitles and his own vocal efforts; nothing crashes.)*

**For his mouth to move while he talks:**
- **AMM Expressions Overhaul** ([Nexus mod 20108](https://www.nexusmods.com/cyberpunk2077/mods/20108)) —
  provides the "Talking" facial anims the lip-flap uses. Without it he still speaks, but his lips stay still.

**For the in-game settings page:**
- **Native Settings UI** (`nativeSettings`) — adds the in-game **Jackie Lives** settings page
  (relationship mode, arrivals, the "Go Home Jackie" recovery button). Get it from
  [Nexus mod 3518](https://www.nexusmods.com/cyberpunk2077/mods/3518).
  - ⚠️ **The folder MUST be named exactly `nativeSettings`** under
    `...\cyber_engine_tweaks\mods\`. `GetMod("nativeSettings")` looks it up *by folder name*; if a
    download extracts to `CP77_nativeSettings-…` or similar, the lookup returns nil, the page never
    appears, and Native Settings' own panel shows *"No mods using native settings installed!"* (that
    message means Native Settings loaded fine but no mod registered with it). Rename the folder if so.
  - ℹ️ **Load order is handled in code, not by you.** CET loads mods alphabetically, so `JackieLives`
    initializes before `nativeSettings`. Rather than register at startup (where `GetMod("nativeSettings")`
    could still be nil), the mod retries every frame until it's available, then registers once. No manual
    load-order setup is needed — just install the dependency. If the page still doesn't show, check the
    CET console for the `[JackieLives]` line: `…panel registered` (success), `…registration FAILED: <err>`
    (report it), or `…not found after retries` (the `nativeSettings` folder is missing or misnamed — see
    the warning above).

## Install

Install the release zip with **Vortex or MO2** — it carries a FOMOD installer, so the manager puts
everything in the right place. To do it **by hand**, extract the zip into your Cyberpunk 2077 folder so
that:

```
bin\x64\plugins\cyber_engine_tweaks\mods\JackieLives\   <- the mod
r6\scripts\JackieLives\JackieLivesVO.reds               <- his voice (do not skip this folder)
r6\audioware\JackieLives\                               <- the old voice system; harmless, ignorable
```

Restart the game after installing. The CET console should print `[JackieLives] Loaded v1.66`.

Updating over an older version is safe — it picks up your existing save. Your settings live in
`jl_settings.txt` next to the mod and survive updates.

## Getting started

**Load a post-Heist save and play normally.** The search for Jackie starts on its own — go see Vik.
A welcome card explains the first step the first time it triggers.

If you'd rather skip straight to it, the settings page has **"Start the search for Jackie"**.
On a **pre-Heist** save the mod stays completely silent, so it can't spoil anything.

Once he's home:

| Do this | How |
|---|---|
| **Talk to him** | Look at him and press **[F]** — a real dialogue box with choices, in the game's own widget |
| **Call him onto a gig** | The **Call Jackie (holocall)** button, or the phone; he arrives from a distance and walks up |
| **Take him to dinner** | Offer it in conversation → pick a restaurant → you get a waypoint → walk there together |
| **Send him off** | Offer it in conversation; he says his goodbye and walks away |
| **Find him** | He keeps a daily schedule around Heywood — walk near one of his spots in its time block |

The CET overlay (default `~`) has the **Jackie Lives** window with the manual buttons, the story-mode
selector and the tuners. It only shows while the overlay is open. You can bind keys for Summon /
Dismiss / Talk in CET's **Bindings** tab.

### How he follows you
- **He walks beside you**, slightly ahead, whenever you're at a walking pace on flat ground — rather than
  trailing on a leash. Don't like it? The settings page's **"Walk beside me"** turns it off and he reverts
  to a plain trailing follower.
- **On stairs and slopes he drops in behind you** and goes single file, then slides back to your side once
  you're on level ground again. (A staircase is rarely two abreast.)
- **When you crouch, he crouches and shadows you** a few metres back, never in front — so he stays out of
  the vision cone you're sneaking through. As a proper companion he's ignored by enemy perception anyway.
- **When you ride a bike, so does he** — his Arch spawns behind you, he mounts, and it trails your bike.
  He's back on foot the moment you get off. (To switch this off, set `Config.cruise.enabled = false` in
  `config.lua`; there's no in-game toggle for it.)
- If you get far enough ahead (a long sprint, a fast-travel), he catches up on his own.

### Call Jackie onto a gig (arrival)
Ask him along and he **arrives from a distance** and walks up as your companion — he never just pops in
next to you. Two **arrival methods**, switchable in the window and on the settings page:
- **FOOT** (default) — spawns ~50 m off to one side of you, sprints in, walks the last stretch.
- **BIKE** — spawns ~60 m back on his Arch, rides in, parks on the road ~20 m out, walks the rest.

He spawns on a valid street at *your* height (not a roof or another floor), and if he ever can't path to
you he respawns a little closer until he reaches you. The CET console logs his distance every few
seconds (`riding in... 44 m to V`) so you can see what he's doing.

He can only be called onto **side jobs**. Try it during a main quest and V declines — "not dragging
Jackie into this mess".

## Relationship mode — Husbando / Hermano

Jackie has two dialogue tracks, set on the **Relationship** section of the settings page:
- **Hermano** *(the default)* — canon: he's your brother-in-arms, strictly choom, still with Misty.
- **Husbando** — he and V have a slow-burn thing, he's more flirty, and he's broken things off with Misty.

**Hermano is used until you pick for yourself**; once you flip the switch, your choice is remembered and
never overridden. It reshapes his talk / holocall / arrival / dismiss lines, the reunion, and the Vik /
Misty / Mama recovery notes.

⚠️ The male-V voice pool is thin (68 clips), so some Hermano lines are **subtitle-only** by design.

## Story modes

Chosen in the CET window. **Quiet Life** is the default and the one all the polished content targets:
the main story plays out as normal and Jackie returns as a living Heywood NPC.

**Blaze of Glory** is an **extremely experimental** alternate timeline where you and Jackie fight out of
the Heist — it **disables the main plot** (no Relic, no Johnny, no dying), must be chosen **before the
Heist**, and **cannot be undone**. It's behind a two-step confirm and lives only in the CET overlay, not
the in-game settings. Treat it as a throwaway-save toy.

## Tuning his spots (optional)

Jackie's schedule spawns him at fixed captured positions. If a seat looks slightly off in your game, the
**Seat position tuner** in the Jackie Lives window nudges it live:

1. Click the **Venue** you want (only venues with a sit spot are listed) — this also sends Jackie there.
   Walk over to him.
2. Slide **X / Y / Z** and **Yaw** (which way he faces) — with **Live** ticked he re-seats as you go.
3. If a venue has more than one stool, use **`< prev seat / next seat >`** to pick which you're editing.
4. **"Print coords → config.lua"** writes the line to the console so you can paste it into `config.lua`
   and keep it.

⚠️ Tuner values are written to their own file and re-applied on load, but anything you type directly into
`config.lua` is yours to maintain — an update overwrites that file.

## Troubleshooting

Open the CET overlay; the console shows lines starting with `[JackieLives]`. The status line in the
window names the common failures:

| Message | Means |
|---|---|
| `Summon failed: Jackie record not found` | Jackie's character record didn't resolve — usually a mod-load-order problem, or TweakDB not ready yet. Wait for the game to settle and try again. |
| `Spawn backend: AMM is selected but not installed` | The Compatibility switch is on but AMM isn't there. Harmless — the mod uses its own spawn instead. Turn the switch off to silence it. |
| `Follower role NOT active … re-applying` | The engine hadn't finished attaching Jackie's body yet. It retries; if it gives up after 5 tries, that log line is what to report. |
| `…not found after retries` | The `nativeSettings` folder is missing or misnamed (see Requirements) |

- **He's silent.** Check that `r6\scripts\JackieLives\JackieLivesVO.reds` is in your game folder — if
  the `r6` folder didn't get extracted, that's the cause. Then check redscript is installed. The console
  log has a `[VO]` line naming which voice path it's using, so you don't have to guess.
- **His lips don't move.** Install AMM Expressions Overhaul.
- **He's lost or stuck.** The settings page has **"Go Home Jackie"**, which despawns and resets him.
- **Nothing happens at all.** Check you're on a post-Heist save, and look for `[JackieLives] Loaded` in
  the console — if that line is missing, the mod isn't installed at the path shown under Install.

Red errors in the console are bugs — please report them on the Nexus **Posts** tab with the console line.

## Files

| File | What |
|---|---|
| `init.lua` | The engine — summon, schedule, follow, arrivals, dinner, dialogue flow, the CET window |
| `config.lua` | The data — locations, schedule, dialogue trees, tuning. **The file to edit** if you're customizing |
| `retrieval.lua` | The "Where's Jackie?" retrieval questline and its shard texts |
| `blaze.lua` | The optional "Blaze of Glory" story mode |
| `dialogui.lua` | Draws V's dialogue choices in the game's own dialogue widget |
| `lang.lua` + `translations.lua` | Localization (Japanese ships; the English string is the key, so anything untranslated falls back to English) |
| `lang_template.lua` | Starting point for a new translation |
| `session.lua` | Session guard — detects a new game / load so stale entity handles are never touched |

---

Fan project, not affiliated with CD PROJEKT RED. **No game assets are distributed.** Requires a legally
owned copy of Cyberpunk 2077. Original code: MIT.
