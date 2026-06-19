# Voice Lines — pipeline, conventions & how to use them

How Jackie's spoken lines get from the game files into the mod, and which new lines
are worth wiring in. **Last updated:** 2026-06-19 (after the 1000-line WolvenKit upgrade).

---

## TL;DR — the one rule

**Whenever you need a line for a new interaction, SEARCH THE NEW POOL FIRST.**
We now have ~1280 lines (777 original + 503 newly extracted). The old 777 were
picked from a narrow scrape; the 503 new ones include far better *generic*
greetings, byes, food/bar, and Heywood/family catch-up lines. Open the tagger,
tick **"new lines only"**, and search the transcript before settling for an old line.

---

## Where everything lives

| Thing | Path | What it is |
|---|---|---|
| Transcripts (all 1280) | `tools/voice-tagger/lines.json` | One entry per line: `id`, `transcript`, `vo_wem`, `source`, tags… |
| New-only transcript dump | `tools/voice-tagger/new_transcripts.tsv` | `stem <tab> transcript`, 505 rows — quick grep target |
| Playable audio bank | `audioware/JackieLives/*.wav` | 1280 clips, full-quality WolvenKit WAV |
| Sound bank manifest | `audioware/JackieLives/JackieLives.yml` | Maps each `sfx` key → a `.wav` file |
| The mod's dialogue/config | `mod/JackieLives/config.lua` | References lines by `sfx = "jl_…"` |
| Tagger web app | `tools/voice-tagger/index.html` | Browse/listen/tag; serve over http (see below) |

**Two id systems (don't mix them up):**
- **Old 777:** keyed by the game's String ID → `jl_<string_id>` (e.g. `jl_1661700260668284928`).
- **New 503:** no String ID, so keyed by their WolvenKit **wem stem** → `jl_<stem>`
  (e.g. `jl_jackie_q000_f_170a4a14f8405008`). `source: "new_unscraped"` in `lines.json`.

Both are real sfx keys in the YML and used identically in `config.lua`.

---

## How a line becomes playable (the full chain)

```
WolvenKit export (.Wav)
   └─ tools/upgrade_audio.py        → renames the 777 known clips to jl_<id>.wav, rewrites YML
   └─ tools/ingest_new_lines.py     → copies the 503 unknown clips into the tagger, stubs lines.json
   └─ tools/whisper_transcribe.py   → fills empty transcripts (Whisper "small", CPU)
   └─ tools/register_new_lines.py   → renames the 503 to jl_<stem>.wav AND adds them to the YML
                                        ⇒ now referenceable from config.lua
```

Re-running any of these is safe (idempotent). `register_new_lines.py` rewrites its
own `# ===== NEW UNSCRAPED LINES =====` block, so re-run it after transcribing more.

## How to actually USE a line in the mod

1. Find the line (tagger or `grep` in `new_transcripts.tsv`). Note its **stem**.
2. Its sfx key is `jl_<stem>` — already in the YML (all 503 are registered).
3. Reference it in `config.lua` exactly like the old lines:

```lua
jackie = { text = "Don't come here often, do ya? Good to see you, cabrón.",
           sfx  = "jl_jackie_q000_m_170f8b95404ea000" },
```

That's it — no YML edit needed, the audio is already in the bank.

> ⚠️ The 2 `civ_low_*` voicemail clips ("number unavailable" / "leave a message")
> are tagger-only — they were **not** copied into the audioware bank, so don't
> reference them in config.lua.

---

## Running the tagger

```powershell
cd C:\Users\ficht002\Documents\Projects\Cyberpunk_modding\tools\voice-tagger
python -m http.server 8080
# then open http://localhost:8080
```

- **"new lines only"** checkbox → just the 503 new ones (orange **NEW** badge).
- New lines have an editable **Transcript** box (Whisper pre-filled it; fix typos by ear).
- Search matches transcript text **and** the id/stem.
- **Export tags** downloads your tags as JSON (localStorage is per-browser, so export to back up).

### Whisper accuracy caveat
Transcripts are auto-generated and ~90% right. It mishears **names** especially
(cabrón→"cabron", chica→"Jika", Misty→"Missy", hermano→"Manor/Mano"). Always
*listen* before committing a line to dialogue, and fix the transcript in the tagger.

---

## Suggested new lines by category

Curated from the 503 new pool — clean, lore-friendly, generic enough to reuse.
All keys verified present in the YML (ready to paste into `config.lua`).

### Greetings
| sfx key | line |
|---|---|
| `jl_jackie_q000_m_170f8b95404ea000` | "Don't come here often, do ya? It's good to see you, cabrón." |
| `jl_jackie_vs_vset_jackie_f_1b4957a4724e2004` | "Hey, you with me, chica?" |

### Accept (V invites him / he's in)
| sfx key | line |
|---|---|
| `jl_jackie_q001_f_16aa0d4dc52ef000` | "Mm-hmm. Let's go." |
| `jl_jackie_q003_f_176e4913884b6000` | "Then let's go. Quicker the better." |
| `jl_jackie_q003_f_17ddf822003fc000` | "Let's do it. Right behind you." |
| `jl_jackie_vs_vset_jackie_f_1f117a347c52a008` | "Hell yeah." |

### Decline / not now
The new pool is **thin** here — most "no" lines are quest-combat specific. Closest:
| sfx key | line |
|---|---|
| `jl_jackie_q005_f_1ad7e378e9405000` | "Uh… don't we gotta check in?" (soft "not now" feel) |

Recommendation: keep the current decline ("Why, what's the rush?") until a cleaner
"raincheck/already busy" line is found. Flag for a future targeted search.

### Bye
| sfx key | line |
|---|---|
| `jl_v_scene_jackie_default_f_1f459b1948494000` | "Alright, I'm out. Take care." |
| `jl_jackie_q003_f_18c517f3d22ef000` | "Hasta luego." |

### What's food / drinks
| sfx key | line |
|---|---|
| `jl_jackie_q001_f_168f93c3cb2ef000` | "Noodles, check. Synth sirloin, check. Get some more chili action up in here, and you're lookin' at Mama Welles' signature sopa de fideos!" |
| `jl_jackie_q000_f_1903f982932ef000` | "Double tequila with grenadine and lime. Nothing better for drowning nerves." |
| `jl_jackie_q005_f_1a43797ce85bf000` | "You gonna have a drink or not?" |

### In-location conversation (Heywood / quiet life / catch-up)
| sfx key | line |
|---|---|
| `jl_v_scene_jackie_default_f_1b2f78230f2c5000` | "Mama Welles — her heart's broken, but she's hangin' in. She's tough." |
| `jl_v_scene_jackie_default_f_1bf91354d84ea008` | "How's your mom?" |
| `jl_v_scene_jackie_default_f_1c226177a42ef000` | "Just askin'. Never thought you'd last that long in a stable, healthy relationship." (teasing) |

> These are *suggestions* — listen in the tagger to confirm tone/delivery before wiring in.
> The `v_scene_jackie_default_*` and `jackie_vs_vset_*` families are the most generic
> (not tied to a quest), so they're the safest reuse candidates.
