# Localization — how Jackie Lives is translated

Jackie Lives ships its authored text (subtitles, notice banners, dialogue
choices, shard, questline cards) in several languages. Audio is **not**
translated — Jackie's voice clips are English-only.

## For players

By default the mod **follows your game's language automatically**. Set
Cyberpunk to Japanese and Jackie's text is Japanese; no extra step. To force a
specific language (e.g. Japanese text over English voice), open
**Esc ▸ Mods ▸ JackieLives ▸ Language** and pick one. Your choice is saved.

### ⚠️ Non-Latin languages (Japanese / Russian / Chinese): two separate fonts

There are **two** renderers with **two** fonts, and non-Latin scripts hit both:

**1. Subtitles / banners / shard — the GAME's font.** The game loads glyphs only
for the language **the game itself is set to**. So Japanese text renders only when
you run the whole game in Japanese; forcing the mod to Japanese while the game is
in English shows **blank subtitles** — the game has no Japanese glyphs loaded.
→ **Set your game language to the language you want, and leave the mod on Auto.**
That's the supported path, and it needs no font install. (This is why "does my PC
have Japanese fonts installed" doesn't matter — the game uses its own bundled
fonts, not Windows'.)

**2. V's choice box — the GAME's font too, since v1.63.** ✅ **Nothing to do.**

Up to v1.62 the choice box was drawn by Cyber Engine Tweaks, whose built-in font
is Latin-only, so translated replies stayed boxes `□□□` for CJK/Cyrillic even when
the game was in Japanese — and the only fix was for the player to install a Noto
font into CET by hand. v1.63 replaced that hand-drawn box with the game's **native
dialogue widget** (`dialogui.lua`), which uses the game's own fonts exactly like
the subtitles do. So point 1 above is now the *whole* story: set your game's
language, leave the mod on Auto, done.

**3. This mod's CET settings window — still CET's font.** The debug/tuning window
(overlay open) is ImGui and remains Latin-only. It's a maintainer tool, not player
text, and none of the story runs through it. If you want it legible in CJK/Cyrillic
anyway, that's a global CET setting, not something a mod can set for you:

1. Download a font with full coverage — **Noto Sans CJK** (JA/ZH) or **Noto Sans**
   (Cyrillic), OFL-licensed and free. A `.ttf`/`.otf`.
2. Put it in `bin\x64\plugins\cyber_engine_tweaks\fonts\`.
3. In `bin\x64\plugins\cyber_engine_tweaks\cyber_engine_tweaks.json`, set the
   `"font"` block's `"path"` to the filename and `"glyph_ranges"` to your script
   (`"Japanese"`, `"ChineseFull"`, `"Cyrillic"`). Restart the game.

## For maintainers

### The mechanism (Lua text — the bulk)

`lang.lua` is the whole runtime. It holds `Lang.t(s)`, which looks a string up in
the active language table and returns the translation, or `s` unchanged if there
is no entry. **The English string itself is the key** — there is no separate key
table, and `config.lua` was not restructured.

`Lang.t` is applied at exactly the text chokepoints every authored line already
flows through:

| # | chokepoint | file | covers |
|---|-----------|------|--------|
| 1 | `showSubtitle` | init.lua | every spoken line (subtitle band) |
| 2 | `showOnscreenMsg` | init.lua | every notice banner |
| 3 | `T()` / `buildHub` title | dialogui.lua | V's dialogue choices + the speaker plate |
| 4 | `buildJackieHub` / `Blaze.showPrompt` | init.lua | the native `[F]` prompt label |
| 5 | `onscreen` / `showTip` | retrieval.lua | questline popups & the welcome card |

Because everything reaches the screen through those, `config.lua`, `blaze.lua`
and `session.lua` needed no edits. `Lang` is a **global** (like `Retrieval` /
`Blaze` / `Session` / `DialogUI`) so it costs no top-level local in init.lua's
200-local chunk.

⚠️ Chokepoint 3 moved out of init.lua in v1.63 (ImGui picker → native dialogue
widget). `dialogui.lua` calls `Lang.t` through its own local `T()` helper at build
time — once per choice when the box opens, rather than once per row per frame as
the old ImGui path did.

Language is chosen in `onInit` *after* `jlLoadSettings`, so an explicit player
pick (persisted as `lang=` in `jl_settings.txt`) beats autodetect. `"auto"` reads
the game's own language setting (`/language OnScreen`, falling back to the
verified `/language VoiceOver`, then English).

### Adding / updating a translation

```
python3 tools/lang_extract.py            # regenerate lang_template.lua from source
python3 tools/lang_extract.py --check ja # report drift for a given language
```

`--check` lists **STALE** keys (an English line was edited, so the translation no
longer matches and silently reverts) and **MISSING** keys (no translation yet →
renders English). Run `--check` after editing any English line. A translation
file is just `lang_<code>.lua` returning `{ ["English"] = "翻訳", ... }`. A missing
or broken file degrades to English with a log line — it can never break loading.

The shipping language codes live in `Lang.LANGUAGES` in `lang.lua`.

### Shards and quest objectives (separate, generated)

A readable shard's words and a tracked objective's tracker line are **not** Lua —
they are the game's own onscreen-localization system, so they have to be baked into
the archive. Both are GENERATED from the storyboard by
`python3 tools/gen_journal_quests.py`, which writes one localization resource per
language:

    archive/source/mod/jackielives/questtext/<locale>/jackielives_questtext.json.json

English comes straight out of `storyboard.lua`/`sidequests.lua`. Other languages are
translated in `tools/journal_text/<locale>.txt` — one record per string, in the
generator's order, separated by a line of `%%`; a blank record falls back to English,
so a half-finished translation is always safe to ship. Re-run the generator after
editing. Turning those sources into the archive is a Windows/WolvenKit step
(`tools/build_archive.py`) and is independent of the Lua translation above.
