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

**2. V's choice box + this mod's settings menu — CET's font.** These are drawn by
Cyber Engine Tweaks, whose built-in font is Latin-only, so they stay boxes `□□□`
for CJK/Cyrillic **even when the game is in Japanese**. One-time fix:

1. Download a font with full coverage — **Noto Sans CJK** (JA/ZH) or **Noto Sans**
   (Cyrillic), OFL-licensed and free. A `.ttf`/`.otf`.
2. Put it in `bin\x64\plugins\cyber_engine_tweaks\fonts\`.
3. In `bin\x64\plugins\cyber_engine_tweaks\cyber_engine_tweaks.json`, set the
   `"font"` block's `"path"` to the filename and `"glyph_ranges"` to your script
   (`"Japanese"`, `"ChineseFull"`, `"Cyrillic"`). Restart the game.

This is a global CET setting (fixes the choice box for *every* CET mod), not
something a mod can set for you. If you skip it, the subtitles still carry the
whole story — only the reply-picker labels are affected.

> **The proper fix for the choice box** (no font install) is to render V's replies
> through the game's *native* dialogue box instead of CET's — then they use the
> game font like the subtitles. That's a planned change; see TODO.

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
| 3 | `drawChoiceRows` / picker title | init.lua | V's dialogue choices |
| 4 | `buildJackieHub` / `Blaze.showPrompt` | init.lua | the native `[F]` prompt label |
| 5 | `onscreen` / `showTip` | retrieval.lua | questline popups & the welcome card |

Because everything reaches the screen through those, `config.lua`, `blaze.lua`
and `session.lua` needed no edits. `Lang` is a **global** (like `Retrieval` /
`Blaze` / `Session`) so it costs no top-level local in init.lua's 200-local chunk.

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

### The shard (separate, WolvenKit)

The Badlands shard's text is **not** Lua — it's the game's onscreen-localization
system, imported through WolvenKit (see `mod/JackieLives_shards/SHARD_SHEET.md`).
Each language is its own resource file: `jl_shards.json` (English) and
`jl_shards.ja-jp.json` (Japanese) hold the same `secondaryKey`s with translated
`femaleVariant`/`maleVariant`. To ship a translated shard, import the matching
`jl_shards.<lang>.json` into the project's localization for that language group.
This is a Windows/WolvenKit step and is independent of the Lua translation above.
