# Reunion dialogue — voiced-line options (first call + first meet)

_Created 2026-07-04. Companion to the TODO item "rewrite the Jackie dialogues with lines we have
transcripts for." Source pool: `audioware/JackieLives/index.json` (777 real Jackie lines, id → text)._

## What this covers

The two **first-reunion** trees in `config.lua`, currently **text-only** (no `sfx`):

- **First phone call** → `Config.reunionCallTree` (config.lua ~1000) — the long emotional call V makes
  after reading the Rocky Ridge shard.
- **First meet** → `Config.reunionMeetTree` (config.lua ~1123) — the short face-to-face when Jackie
  walks in.

> `Config.firstCallTree` (the old bike-back call) is **superseded** by `reunionCallTree` per the code
> comment, so it's not touched here.

## The hard truth up front (so you can choose well)

Every line in `index.json` is Jackie's **real in-game voice**, but he **never had a "back from the
dead" scene** — so no transcript line actually says "I'm alive," "I'm sorry I let you mourn me," or
"there's a tracking daemon in my skull." That means:

- **Only Jackie's lines can ever be voiced.** V's choice lines are the *player's* picks — we have no V
  audio in this bank, so V stays text on-screen in both options. (A separate 80-line **memorial** set
  of *V calling Jackie's dead line* exists — "I went to your funeral" — but it's not in this file and
  is a future, separate idea.)
- **The more we voice, the more the story bends** toward what Jackie actually said on tape. Fully
  voiced = his real voice throughout, but the precise emotional beats (mourning, the daemon, "I'm
  sorry") get softer/looser. Minimal = keeps your exact bespoke writing, voice only where a real line
  genuinely fits.

That trade-off is the whole reason there are two versions below.

---

# OPTION A — Fully voiced (every Jackie line is a real transcript line)

Goal: when this plays, **every word out of Jackie is his real voice.** The beats are re-shaped to fit
lines that exist. Reads a little more like "old Jackie being Jackie" and a little less like a scripted
resurrection — but it's 100% him.

### A · First phone call (`reunionCallTree`)

| Node | Voiced Jackie line (real) | `sfx` id | Fit |
|---|---|---|---|
| pickup | "V, hey! ¿Cómo te sientes?" | `jl_1867549271199477760` | ✅ warm surprised pickup |
| alive | "Eh, you know how it is, can't complain, but... we ain't here to shoot the shit about me." | `jl_1861666308579323904` | ⚠️ deflects instead of apologizing |
| outrage | "Talk to me, choomba." | `jl_2239163066690486272` | ⚠️ "let me have it" tone, loose |
| whatyou | "Now siddown and tell me what's got your shorts in a knot." | `jl_1692474422040915968` | ✅ "tell me everything" |
| deflect | "Yep, don't gotta tell me." | `jl_1989698662345547776` | ✅ "you go quiet, I won't push" |
| hiding | "Now I go back, find Misty and we do somethin' to make me feel alive again." | `jl_1677043911795367936` | ✅ wants to come home |
| daemon | "Worried 'bout me. Been for a while." | `jl_2028635009449914368` | ⚠️ gestures at danger, not the daemon |
| quest | "You're all right." | `jl_1885197235896905728` | ✅ "you'd really do that for me" warmth |
| gigs | "Years of mercwork, and yet – still sweat like a roasted pig when I talk to my ma." | `jl_1795303665032519680` | ✅ Mama beat, no more gigs |
| askbike | "Listen, chica, I got this thing. Mind if I borrow your wheels?" | `jl_1866205008628969472` | ✅ segues into the bike ask |
| bike / bikesafe | "Can't help herself, y'know – checkin' to see if I'm not rottin' in some dumpster... like most of the Welles boys." | `jl_1964635881791627264` | ⚠️ family/dark-humor filler for the nervous beat |
| coming | "Hold on, V, I'm comin'." | `jl_1714251940705820672` | ✅ on my way |
| onmyway | "Made it. Almost at your place." | `jl_1866275454447677440` | ✅ arriving (terminal → `reunion_arrival`) |

⚠️ = beat is bent to fit an existing line. To keep the branch shape identical, some multi-node beats
(bike / bikesafe) collapse to one voiced idea.

### A · First meet (`reunionMeetTree`)

| Node | Voiced Jackie line (real) | `sfx` id | Fit |
|---|---|---|---|
| seeya | "Don't come here often, do ya? Heheh. It's good to see you, chica." | `jl_1661700260668284928` | ✅ perfect face-to-face greeting |
| used | "You're all right." | `jl_1885197235896905728` | ✅ warm |
| bikeask | "Listen, chica, I got this thing. Mind if I borrow your wheels?" | `jl_1866205008628969472` | ✅ the bike |
| leave | "Aah, savin' my ass, V, thank you. How about I drive you home, eh?" | `jl_1866254590956171264` | ✅✅ "take me home" — near-perfect closer (terminal → `reunion_complete`) |

Alt closers if you prefer: "Hey, hermana. Your new life... it starts now." (`jl_2231669070565130240`)
or "Now let's get outta here. I'm dyin' for some fresh air." (`jl_1676583523110838280`).

---

# OPTION B — Keep the writing, add voice only where it truly fits

Goal: **don't touch your bespoke emotional script.** Leave the current text exactly as written, and
add `sfx` to the handful of nodes where a real line lands close enough that Jackie's voice can carry
your subtitle. Everywhere else stays text-only (subtitle, no audio) — which already works with no crash.

> How it works technically: a node's on-screen subtitle is the `text`; the `sfx` just picks which audio
> clip plays under it. The audio's *actual words* won't match your subtitle exactly — but for a short,
> tonally-right clip that usually reads fine (the game does this too). Where the mismatch would be
> jarring, leave it text-only.

### B · First phone call (`reunionCallTree`) — voice these nodes only

| Node | Keep your text | Add `sfx` | Why it's safe |
|---|---|---|---|
| pickup | "...V? (a breath) Dios mío, it's really you..." | `jl_1867549271199477760` ("V, hey! ¿Cómo te sientes?") | warm, breathy, short — reads as the same beat |
| whatyou | "So talk to me. What'd I miss?..." | `jl_1692474422040915968` ("Now siddown and tell me what's got your shorts in a knot.") | same "tell me everything" energy |
| coming | "...Where you at? Nah — don't move, I'm already headed your way..." | `jl_1714251940705820672` ("Hold on, V, I'm comin'.") | literally the same idea |
| onmyway | "Countin' on it. See you real soon, V." | `jl_1866275454447677440` ("Made it. Almost at your place.") | on-his-way farewell |

All **other** call nodes (alive / outrage / deflect / hiding / daemon / quest / gigs / askbike / bike /
bikesafe) stay **text-only** — their content is too specific (mourning, the daemon, Mama, the nervous
bike ask) for any real clip to match honestly.

### B · First meet (`reunionMeetTree`) — voice these nodes only

| Node | Keep your text | Add `sfx` | Why it's safe |
|---|---|---|---|
| seeya | "(quiet) ...Look at you. In the flesh..." | `jl_1661700260668284928` ("...It's good to see you, chica.") | ✅ near-exact match |
| leave | "(grins) Then what're we waitin' for?... Take me home, V." | `jl_1866254590956171264` ("...How about I drive you home, eh?") | ✅ "take me home" match |

`used` and `bikeask` stay text-only (optional: add `jl_1885197235896905728` "You're all right." to
`used` if you want one more voiced beat).

---

## Summary / recommendation

- **Want the whole reunion in his real voice, accept looser beats → Option A.**
- **Want to protect your emotional script, voice only the safe moments → Option B.** _(recommended —
  the reunion's power is in the specific writing, and B keeps 100% of it while still opening with his
  real voice and closing on "take me home.")_

**No manifest work needed either way:** every `jl_<id>` above is already in
`staging/r6/audioware/JackieLives/JackieLives.yml` (the bank lists all lines). Adding `sfx` to a node
just makes it play once the user has the audio installed; with no audio it silently stays subtitle-only.

_To apply a choice, say which option (or mix) and I'll edit `config.lua`._
