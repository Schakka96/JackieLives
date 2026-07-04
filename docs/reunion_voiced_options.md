# Reunion dialogue — voiced-line plan (first call + first meet)

_Updated 2026-07-04. **DECIDED (Antonia):** keep the full emotional bespoke subtitles, drop in a few
real voiced lines where they genuinely fit. Source pool: `audioware/JackieLives/index.json`._

## ⚠️ Line-pool caveat — only 777 of the ~1281 lines are searchable on the Mac

The voice bank (`JackieLives.yml`) lists **1281** lines, but only the **777** in `index.json` have
**text** on this machine. The other **504** are the Whisper-transcribed "new" lines whose transcripts
live in `lines.json` on the **Windows** box (gitignored → never synced here), so they can't be searched
from the Mac. To open them up, do ONE of these on Windows and sync it:
- re-run the transcript export so `index.json` includes all 1281 (best), **or**
- copy `tools/voice-tagger/lines.json` into the repo temporarily so I can read the 504 transcripts.

Everything below is chosen from the 777 available now — searched hard across bike / joy / gratitude /
farewell / warmth buckets.

## How voiced lines work here (important)

A node plays ONE audio clip (`sfx`) under its on-screen subtitle (`text`). To avoid a dubbed-wrong feel,
**voiced nodes set the subtitle = the clip's real words**; the surrounding **text-only** nodes carry the
bespoke emotional writing that has no matching audio. Only **Jackie** can be voiced — V's lines are the
player's picks (no V audio in this bank), so V always stays text.

---

# FIRST MEET — restructured (`Config.reunionMeetTree`)

New shape you asked for: warm greeting → he offers to drive V home → **V: "but didn't you want your
bike?"** → he lights up about his Arch → they head off. Voiced nodes = 🔊.

| Node | Speaker line (subtitle) | Voiced? |
|---|---|---|
| **seeya** | 🔊 "Don't come here often, do ya? Heheh. It's good to see you, chica." | `jl_1661700260668284928` ✅ (your locked pick) |
| ↳ V | "You've looked better yourself, choom." / "(just look at him a moment) ...It's you." | text |
| **used** | "(laughs, pulls you into a rough hug) Yeah, yeah — desert don't do a man's looks any favors. But you? Damn, you're a sight, V." | text-only (bespoke) |
| ↳ V | "We're both still standin'. That's what counts." | text |
| **drivehome** | 🔊 "Aah, savin' my ass, V, thank you. How about I drive you home, eh?" | `jl_1866254590956171264` |
| ↳ V | "Drive me home? Didn't you wanna ride your girl? Your Arch's right where you left her." | text |
| **bikejoy** | 🔊 "Aa, a heart o' gold? 'Cause only somebody with a heart o' gold can understand just how much I need to get back to my girl." | `jl_1866269806381133824` ⭐ new find |
| ↳ V | "(laughs) Go on then, hermano. She's missed you." | text |
| **rideout** (terminal → `reunion_complete`) | 🔊 "Now let's get outta here. I'm dyin' for some fresh air." | `jl_1676583523110838280` |

That's **4 voiced Jackie beats** (greeting, drive-home, bike-joy, ride-out) wrapped around the bespoke
hug/banter. `bikejoy` (`jl_1866269806381133824`) is the standout — it's literally Jackie gushing about
"my girl" (his bike), so his real voice lands exactly on the beat you described.

**Swap options if you want a different flavour:**
- bike-joy alt: 🔊 "Some top-notch work, Miguel did. Rides like it looks – factory new." (`jl_1628830076146479104`) — admires her condition instead.
- ride-out alt: 🔊 "Vámonos." (`jl_1688508282677452800`) — short & punchy · or "You and me, we're gonna get along fine." (`jl_1804217704801824768`) — warm.

---

# FIRST CALL — voiced picks (`Config.reunionCallTree`)

Keep your whole emotional call script; voice only these four nodes (real clips that match your beat),
leave the mourning / daemon / Mama / nervous-bike nodes text-only.

| Node | Add `sfx` | Real clip words |
|---|---|---|
| **pickup** | `jl_1867549271199477760` | "V, hey! ¿Cómo te sientes?" |
| **whatyou** | `jl_1692474422040915968` | "Now siddown and tell me what's got your shorts in a knot." |
| **coming** | `jl_1714251940705820672` | "Hold on, V, I'm comin'." |
| **onmyway** (terminal) | `jl_1866275454447677440` | "Made it. Almost at your place." |

(If you'd rather match subtitles exactly, set those four subtitles to the clip words above; otherwise
leave your bespoke subtitle and accept a loose audio match on the call.)

---

## ✅ IMPLEMENTED (v0.93)

- **First meet** restructured exactly as above: `seeya` → `used` (hug) → `drivehome` → V: "didn't you
  want your bike?" → `bikejoy` → `leave` (ride out). 4 voiced Jackie beats, bespoke hug in the middle.
- **First call**: added the voiced **`iffy`** node (Antonia's pick — `jl_1918251744810168320`,
  "…for a sec there things looked iffy…") between `outrage` and `whatyou`, and voiced the final
  `onmyway` sign-off (`jl_1866275454447677440`).
- **Reunion smile boost** (`Config.smile.reunion*`): Jackie is forced to smile for the first 8 s of the
  meet, then rolls smiles at **3× the normal chance** for the rest of that chat, rotating his two happy
  faces (idle 6 = Smile, 5 = Joy). It **yields to his mouth flap** so his spoken lines still lip-sync
  (the smile fills the gaps) — same rule the rest of the mod uses so a smile never freezes his mouth.

_Still open:_ the other **504** Whisper-transcribed lines aren't on the Mac — sync `lines.json` /
regenerate `index.json` from Windows and I'll re-search the full 1281 for even better fits.
