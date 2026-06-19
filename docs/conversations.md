# Jackie — Conversations & Line Bank

A writing/content reference for Jackie's dialogue. Every Jackie line below is matched to a **real
voice clip** from the 777-line bank, named `jl_<id>` (an Audioware event). To use a line in-game,
drop its `sfx = "jl_<id>"` into a node in `config.lua` (e.g. `Config.locationDialogue`,
`Config.callTree`). No code changes needed — it's data-driven.

**V has no voice files**, so every V line is a **silent text choice** (like the game's dialogue
wheel). That means V's wording is free — we can write anything; only Jackie's lines must map to a clip.

### Legend
- ✅ **clean** — the clip says exactly this, ready to use.
- ✂️ **TRIM** — the clip contains *extra words*; needs cutting in audio. The full clip text is shown.
- ✏️ **ANTONIA EDIT** — you flagged this as needing your call on where to cut / how to use.
- ⭐ **RARE** — play at a low probability (chance noted).
- ❓ **DESIGN** — placement/flow still to be decided.

> Status: as of v0.34, **none** of these lines are wired in yet — the live trees use a different
> 23-clip set. This bank is the pool to pull from next.

---

## 1. Greetings (extra pool)

Add these to the greeting `jackiePool`s (face-to-face talk openers and/or the call ring).

| Jackie line | `sfx` | Notes |
|---|---|---|
| V, hey! ¿Cómo te sientes? | `jl_1867549271199477760` | ✅ warm check-in |
| ¿Qué onda? | `jl_2015561179233951744` | ✅ casual |
| Catch, chica! | `jl_2009811489618063360` | ✅ tossing something your way — situational |
| Huh? | `jl_1989698665969426460` | ✅ if you walk up while he's distracted |
| About time. | `jl_1934361222363238400` | ✅ pair with a laugh event (`ono_jackie_laughs_soft`) so it lands light, not annoyed |
| Leave it to me, chica. I'm drivin'. | `jl_1896571740950261760` | ✅ only fits a driving/vehicle context |
| Checkin' to see if I'm not rotting in some dumpster, like most o' the Welles boys? | `jl_2008332149470457856` | ⭐ **1% chance** — dark family humor |

---

## 2. Agreement — "yes, I'll come on the job"

Jackie's reply when V asks him onto a SIDE gig (the gig-accept node). All ✅ clean — rotate for variety.

| Jackie line | `sfx` |
|---|---|
| Yeah, OK. | `jl_1883858553243889664` |
| All right, all right, all right. | `jl_1777953524587360256` |
| Right on, chica. | `jl_1721407637774192672` |
| You're all right. | `jl_1885197235896905728` |
| Shit's finally happenin'... | `jl_1989698661036924960` |
| Too late to back out now. Come on, V. | `jl_1989698664946016264` |
| And we'd best be quick. | `jl_1616247819348959232` |
| You comin'? Time's precious. | `jl_1989698664979570696` |
| So? You ready? | `jl_1902765821582520320` |
| Got me right behind you. | `jl_1679806464288055296` |
| Sí, sí, me acuerdo. | `jl_1989559098138238976` |
| Buen trabajo, V. | `jl_1947679354367393792` |
| Yeah, you too. | `jl_2253378878733631488` |
| Anyway, what's goin' on? | `jl_1878047791342612480` |
| We'll snap their necks before they realize. | `jl_1719792744366325760` |
| Heh, City Hall should be fuckin' thankin' us! | `jl_1989660111004311552` ⭐ **rare** |

---

## 3. Future lines — need your edit (✏️ TRIM)

The clip for each of these carries extra words. Decide the cut point; I'll mark them ready once you do.

| You want | `sfx` | Full clip (✂️ cut to taste) |
|---|---|---|
| The good life, I mean. | `jl_1993485821649166336` | "*Yorinobu Arasaka.* The good life, I mean." — drop the prefix |
| I got a question. | `jl_1724324756157419520` | "I got a question. *When do we get to the real reason we're all here?*" |
| Sin problemas. | `jl_1866394972076257280` | "Sin problemas. *Meet you by the Delamain.*" |
| Mm! Woman of the hour! | `jl_1567632940189503488` | "Mm! Woman of the hour! *Sheesh, it took you long enough! Worked up an appetite just waitin'!*" — or keep the whole thing as a **date greeting** |
| Le'ss go, chica. | `jl_2238683896952672256` | "Le'ss go, chica. *Pop 'er open.*" |
| Better fuckin' believe I will! | `jl_1989701653035294720` | "*Son of a bitch!* Better fuckin' believe I will!" |
| You scheme yet? You got a plan? | `jl_1671091734673317888` | "*Well, whatever. Let's go get this tech.* You scheme yet? You got a plan?" |
| You have a good evening, now. | `jl_1866272726522687488` | "You have a good evening, now, *officer... ma'am.*" |

---

## 4. "Are we using these awesome lines anywhere?" — no, but here's where they fit

Not wired yet. Proposed homes below. All ✅ clean unless noted.

| Jackie line | `sfx` | Proposed use |
|---|---|---|
| Gettin' one of my good feelings. | `jl_1834502468175589376` | greeting / pre-gig flavor |
| 'Course I do. What, the fixer didn't give you the job detes? | `jl_1660505895391481856` | gig branch — when V asks if he knows the job |
| Elaborate, I wanna hear it. | `jl_1724304566086586368` | gig branch — he wants details. ❓ V's text reply: *"Let's off some gonks."* |
| Don't worry, got this. | `jl_1725480866495123456` | reassurance after agreeing |
| Madres, V... This is the most important day of my fuckin' life. | `jl_1989802901134712832` | big-moment / special quest beat |
| Hey, hermana. Your new life... it starts now. | `jl_2231669070565130240` | special quest — retrieval payoff |
| Ka-ching, baby! | `jl_1927336253241237504` | gig success / reward |

### Date / food initiation (need ≥3 openers — these are your 3)
Either V proposes (text choice) or **Jackie** opens with one of these:

| Date opener (Jackie) | `sfx` |
|---|---|
| Man, I'm starvin'. Let's grab a tight-bite. Whaddaya say? | `jl_1904096844380655616` |
| Now, whaddaya say we liquor up and talk life. | `jl_1661715724513484800` |
| C'mon. I'm fuckin' starved. | `jl_1834512408575406080` |

---

## 5. Scene — Going on a date

A small branching scene; openers above. V lines are text-only.

1. **Open** — Jackie (one of the 3 date openers above), or V proposes it as a text choice.
2. **Agree to go out** — Jackie: *"Just don't forget to suit up."* `jl_1902710645647618048`
3. **During the date** — Jackie: *"'Ey, oh, V — just one more thing…"* `jl_1767705106931474432`
   → *"'Bout us. Sense a kind of chemistry, y'know?"* `jl_1834510517900603392`
4. **V asks if he likes her** (text choice) → Jackie: *"Well, uh, maybe a little."* `jl_1730327816763797504`
5. **End — V starts to leave** (text choice) → Jackie: *"Why, what's the rush?"* `jl_1989527454849245184`

---

## 6. Scene — The Retrieval Quest (unlocks Jackie + the companion mod)

The quest where V learns Jackie's alive and brings him back. V follows a "Rumor" trail, finds him
running a bar in the Badlands. They talk about where he's been, his recovery, and the job that
"killed" him. **V refuses to share details about the chip/Relic** to protect him. Jackie agrees to
lay low and try the quiet life — but swears he'll protect V if she ever needs him.

> All Jackie lines below are real clips; V lines are text-only. ✂️ = trim needed (full clip shown).

**A. The reveal** (option: Jackie walks in mid-conversation between V and someone else)
- Jackie: *"No, he's alive, well and kickin'. An' he sends his regards."* `jl_2343235010488000512`

**B. First meeting again — the Badlands bar**
- Jackie: *"Oh, was worried I'd have to turn to farming. Heh! Ehh… sure hope you're here for me."* `jl_1660215901783347200`
- Jackie: *"Bar don't look too shabby."* `jl_1785207824325685248`

**C. About his mom / quitting the merc life**
- Jackie: *"Ehh, y'know. She's worried about me — whatever."* `jl_1795303424698900480`
  *(He concedes: no big gigs anymore — just simple, lay-low stuff.)*

**D. The failed job**
- Jackie: *"Smooth as fuckin' sandpaper."* `jl_1989806945953718272` *(sarcastic — how it went)*
- Jackie: *"What, fuckin' nature-walked it rest of the way?"* `jl_1908383776933695488` *(asking how she got out / fixed the Relic mess)*
- Jackie: *"Well?"* `jl_2198446477823139840`

**E. V's choice — tell him everything, or protect him**
- Jackie: *"C'mon, no fear. Trust me."* `jl_2239013707474714624`
  *(If V chooses to tell all → **Johnny interrupts her** before she can.)*
- Jackie (✂️): *"You sleep better the less you know."* `jl_1804295543584649216`
  — full clip: "You sleep better the less you know. *Got no idea myself, and that's a good thing.*"
- Jackie (✏️ partial): *"Don't worry…"* — cut from `jl_1725480866495123456` ("Don't worry, got this.")

**F. V says she's got stuff to handle (won't share the details)**
- Jackie: *"Agh, esa chamba te va a matar."* `jl_1793962760102408192` — then —
- Jackie: *"Buena suerte."* `jl_1877989126535311360`

**G. Jackie offers help going forward**
- Jackie: *"Ehh… brought wheels with ya? Sure could use some."* `jl_1908400584180912128`
- Jackie: *"But don't you worry. Lemme help you find digs. You gotta live somewhere."* `jl_1740241310388776960`

---

## 7. Line dump — 2026-06-19 (Antonia) — to place

Brackets `[ ]` = the part Antonia will **cut from the clip** in audio; the un-bracketed text is what plays.

### 7a. Goodbyes / partings — for BOTH phone hang-up and dismiss
| Line (after trim) | `sfx` | Notes |
|---|---|---|
| Ahí luego, V. | `jl_1698516624514703372` | ✅ **4 separate recordings — rotate all of them** (this + next 3) |
| Ahí luego, V. | `jl_1790892452886372352` | ✅ recording #2 |
| Ahí luego, V. | `jl_1697051347046326288` | ✅ recording #3 |
| Ahí luego, V. | `jl_1790930025243500544` | ✅ recording #4 |
| Ahí luego. | `jl_1754957630472646704` | ✂️ "[Don't forget to let Dex know we got his toy for him.] Ahí luego." — trim to the sign-off |
| Better get goin'. | `jl_1967553783536623616` | ✅ also a **stock goodbye** line |
| Hey V... just keep an eye out, OK? | `jl_1767765385102974976` | ✅ caring parting |

### 7b. "Stop / hold up" flavor (mid-walk / outing)
| Line (after trim) | `sfx` | Full clip |
|---|---|---|
| Gonna stop here, need to sort out a few things before we go on. | `jl_1771945225346895872` | ✂️ "[Place looks deserted.] Gonna stop here, need to sort out a few things before we go on." |

### 7c. Favor / setup
| Line (after trim) | `sfx` | Full clip / variant |
|---|---|---|
| Listen, chica, I got this thing. | `jl_1866205008628969472` | ✂️ "[Mind if I borrow your wheels?]" — variant "Listen, amiga..." `jl_2008326330108538880` |

### 7d. Negatives — too abrupt alone, PAIR with a warm follow-up
| Bare "no" line (after trim) | `sfx` | Trimmed-off tail |
|---|---|---|
| Nah, chica. | `jl_1866261886444662784` | ✂️ "[Not just any other city.]" |
| Nah. | `jl_2192574119410593792` | ✂️ "[Said it didn't suit her, uh, "style" – hah. You'll see what I mean.]" |
| Nah, no way, | `jl_1785253540930662400` | ✂️ "[our guy had a saggier neck, many, many folds.]" |

Warm follow-ups to splice after a bare "Nah" (Antonia: combine so it's not abrupt):
| Follow-up | `sfx` | Full clip |
|---|---|---|
| Me 'n' Misty got a little catchin' up to do. | `jl_1614041695221669888` | ✂️ "[I'll sit tight over here.] Me 'n' Misty got a little catchin' up to do." |
| Sorry, V. | `jl_1888115393428475904` | ✂️ "[Agh. Scratched your baby up pretty bad.] Sorry, V." |
| Now I go back, find Misty. | `jl_1677043911795367936` | ✂️ "Now I go back, find Misty[ and we do somethin' to make me feel alive again.]" (full version already used in the Misty location tree) |

### 7e. Lunch suggestion
**"C'mon, let's go have some lunch."** `jl_1834500545020096512` — already wired into the noodle-bar greeting pool
(`Config.locationDialogue.noodle`). ❓ Also good as a **post-gig** suggestion so JACKIE can open a lunch/date
invite himself (not only V).

---

## 8. Dinner / date payment arc (DESIGN ❓)

A running gag tied to Jackie's "I quit the merc life, I'm broke now" plot.

- **Date 1 — first time V invites him to eat:** Jackie: *"Uh, I ain't gonna lie... I'm a bit light. I can't
  pay you now."* `jl_1885122683250601984` → V (text): *"My treat."* Matches him being out of merc money.
- **Date 3 — the fancy spot:** Jackie suggests a high-end bar. ❓ **Which?** — proposed **Embers** (the
  Michelin-tier place from the heist briefing; most lore-fitting "fancy"; alt: Afterlife VIP / Empathy).
  If V asks (playfully) whether *he's* paying this time / will live off her merc money forever:
  - Jackie: *"Come on, chica. You know I was raised right."* `jl_2028600518010400768`
  - then he orders: *"Two Tequila Old Fashioneds with a splash of cerveza and a chili garnish."*
    `jl_1721401856077123596` (singular variant: "A Tequila Old Fashioned..." `jl_1721408614996692992`)
- **Split-the-bill option:** Jackie: *"Yeah, partner. We'll go halfsies."* `jl_1660742685327118336`
- More date flavor already in the bank: *"You comin'? Time's precious."* `jl_1989698664979570696` ·
  *"Sin problemas. [Meet you by the Delamain.]"* `jl_1866394972076257280`

### Afterlife as a date venue — ACCEPT line
When V invites Jackie specifically to the **Afterlife**, he accepts with:
*"[But that's done after tomorrow.] Afterlife, here we come, baby! Yeah!"* `jl_1658860298971172864` (✂️ trim prefix).

---

## 8.1 Scene — Date 3 at Embers (script)

The pay-off date in Jackie's "broke ex-merc" arc: after two outings on V's tab, the **3rd dinner** he proposes
a *fancy* spot himself — **Embers** (the Michelin-tier place from the heist briefing) — and insists on paying.

**Prerequisites to wire (not yet built):**
- A **completed-dinner counter** (`JL.dinner.count`, ++ when a meal finishes in `dinnerTick`). Fire this scene
  the first time `count == 2` and the next dinner triggers (i.e. the 3rd), then fall back to the normal flow.
- **Embers coordinates** captured into `Config.date.restaurants` (key `embers`) — pos/yaw still TODO.
- Reuses the existing walk → seat → linger state machine; only the dialogue + "who pays" beat are new.

All Jackie lines are real clips; V lines are silent text. ✂️ = trim (full clip shown).

1. **Jackie proposes (instead of the usual jackieOpen line):**
   Jackie: *"Now, whaddaya say we liquor up and talk life."* `jl_1661715724513484800`
   → V choices: **"Somewhere nice for once?"** → `embers` · **"Maybe later."** → `decline`
2. **The "who pays" beat (playful):** V (text): *"You buyin' this time, or livin' off my eddies forever?"*
   → Jackie: *"Come on, chica. You know I was raised right."* `jl_2028600518010400768`
3. **Seated at Embers — he orders for them both:**
   Jackie: *"Two Tequila Old Fashioneds with a splash of cerveza and a chili garnish."* `jl_1721401856077123596`
   *(singular variant if it's just drinks for one: "A Tequila Old Fashioned…" `jl_1721408614996692992`)*
4. **Optional split:** V (text): *"We can go halfsies."* → Jackie: *"Yeah, partner. We'll go halfsies."*
   `jl_1660742685327118336`
5. **Leave:** V walks off → Jackie (stand-up line): *"Sin problemas. [Meet you by the Delamain.]"*
   `jl_1866394972076257280` (✂️ trim the Delamain tail), or reuse the standard get-up line.

### Implementation-ready node sketch (drop into `Config.date.tree` once `embers` coords + counter exist)
```lua
embersOpen = {   -- entered only on the 3rd dinner (Jackie-proposed)
  jackie  = { text = "Now, whaddaya say we liquor up and talk life.", sfx = "jl_1661715724513484800" },
  choices = {
    { text = "Somewhere nice for once?", to = "embersPay" },
    { text = "Maybe later.",             to = "decline"   },
  },
},
embersPay = {
  jackie  = { text = "Come on, chica. You know I was raised right.", sfx = "jl_2028600518010400768" },
  choices = {
    { text = "Your treat, then.",   to = nil, action = "dine:embers" },
    { text = "We'll go halfsies.",  to = "embersSplit" },
  },
},
embersSplit = {
  jackie  = { text = "Yeah, partner. We'll go halfsies.", sfx = "jl_1660742685327118336" },
  choices = { { text = "Deal. Let's eat.", to = nil, action = "dine:embers" } },
},
```
*(The seated order line `jl_1721401856077123596` would play as the `doneText`-style beat on sitting at Embers —
i.e. a per-venue override of the seated line, another small addition.)*

---

## Appendix — quick line → clip index

Every line above, flat, for ctrl-F:

```
GREETINGS
jl_1867549271199477760  V, hey! ¿Cómo te sientes?
jl_2015561179233951744  ¿Qué onda?
jl_2009811489618063360  Catch, chica!
jl_1989698665969426460  Huh?
jl_1934361222363238400  About time.
jl_1896571740950261760  Leave it to me, chica. I'm drivin'.
jl_2008332149470457856  Checkin' to see if I'm not rotting in some dumpster... (1% rare)

AGREEMENT
jl_1883858553243889664  Yeah, OK.
jl_1777953524587360256  All right, all right, all right.
jl_1721407637774192672  Right on, chica.
jl_1885197235896905728  You're all right.
jl_1989698661036924960  Shit's finally happenin'...
jl_1989698664946016264  Too late to back out now. Come on, V.
jl_1616247819348959232  And we'd best be quick.
jl_1989698664979570696  You comin'? Time's precious.
jl_1902765821582520320  So? You ready?
jl_1679806464288055296  Got me right behind you.
jl_1989559098138238976  Sí, sí, me acuerdo.
jl_1947679354367393792  Buen trabajo, V.
jl_2253378878733631488  Yeah, you too.
jl_1878047791342612480  Anyway, what's goin' on?
jl_1719792744366325760  We'll snap their necks before they realize.
jl_1989660111004311552  Heh, City Hall should be fuckin' thankin' us! (rare)

NEED EDIT (trim)
jl_1993485821649166336  [Yorinobu Arasaka.] The good life, I mean.
jl_1724324756157419520  I got a question. [When do we get to the real reason...]
jl_1866394972076257280  Sin problemas. [Meet you by the Delamain.]
jl_1567632940189503488  Mm! Woman of the hour! [Sheesh, it took you long enough!...]
jl_2238683896952672256  Le'ss go, chica. [Pop 'er open.]
jl_1989701653035294720  [Son of a bitch!] Better fuckin' believe I will!
jl_1671091734673317888  [Well, whatever. Let's go get this tech.] You scheme yet? You got a plan?
jl_1866272726522687488  You have a good evening, now. [officer... ma'am.]

AWESOME / MISC
jl_1834502468175589376  Gettin' one of my good feelings.
jl_1660505895391481856  'Course I do. What, the fixer didn't give you the job detes?
jl_1724304566086586368  Elaborate, I wanna hear it.
jl_1725480866495123456  Don't worry, got this.
jl_1989802901134712832  Madres, V... This is the most important day of my fuckin' life.
jl_2231669070565130240  Hey, hermana. Your new life... it starts now.
jl_1927336253241237504  Ka-ching, baby!

DATE
jl_1904096844380655616  Man, I'm starvin'. Let's grab a tight-bite. Whaddaya say?
jl_1661715724513484800  Now, whaddaya say we liquor up and talk life.
jl_1834512408575406080  C'mon. I'm fuckin' starved.
jl_1902710645647618048  Just don't forget to suit up.
jl_1767705106931474432  'Ey, oh, V — just one more thing…
jl_1834510517900603392  'Bout us. Sense a kind of chemistry, y'know?
jl_1730327816763797504  Well, uh, maybe a little.
jl_1989527454849245184  Why, what's the rush?

RETRIEVAL QUEST
jl_2343235010488000512  No, he's alive, well and kickin'. An' he sends his regards.
jl_1660215901783347200  Oh, was worried I'd have to turn to farming. Heh! Ehh… sure hope you're here for me.
jl_1785207824325685248  Bar don't look too shabby.
jl_1795303424698900480  Ehh, y'know. She's worried about me — whatever.
jl_1989806945953718272  Smooth as fuckin' sandpaper.
jl_1908383776933695488  What, fuckin' nature-walked it rest of the way?
jl_2198446477823139840  Well?
jl_2239013707474714624  C'mon, no fear. Trust me.
jl_1804295543584649216  You sleep better the less you know. [Got no idea myself...]
jl_1908400584180912128  Ehh… brought wheels with ya? Sure could use some.
jl_1793962760102408192  Agh, esa chamba te va a matar.
jl_1877989126535311360  Buena suerte.
jl_1740241310388776960  But don't you worry. Lemme help you find digs. You gotta live somewhere.

LINE DUMP 2026-06-19 (brackets = Antonia trims them out)
jl_1698516624514703372  Ahí luego, V.                (goodbye — recording 1/4)
jl_1790892452886372352  Ahí luego, V.                (goodbye — recording 2/4)
jl_1697051347046326288  Ahí luego, V.                (goodbye — recording 3/4)
jl_1790930025243500544  Ahí luego, V.                (goodbye — recording 4/4)
jl_1754957630472646704  [Don't forget to let Dex know we got his toy for him.] Ahí luego.
jl_1967553783536623616  Better get goin'.            (also stock goodbye)
jl_1767765385102974976  Hey V... just keep an eye out, OK?
jl_1771945225346895872  [Place looks deserted.] Gonna stop here, need to sort out a few things before we go on.
jl_1866205008628969472  Listen, chica, I got this thing. [Mind if I borrow your wheels?]
jl_2008326330108538880  Listen, amiga, I got this thing. [Mind if I borrow your wheels?]  (variant)
jl_1866261886444662784  Nah, chica. [Not just any other city.]
jl_2192574119410593792  Nah. [Said it didn't suit her, uh, "style" – hah. You'll see what I mean.]
jl_1785253540930662400  Nah, no way, [our guy had a saggier neck, many, many folds.]
jl_1614041695221669888  [I'll sit tight over here.] Me 'n' Misty got a little catchin' up to do.
jl_1888115393428475904  [Agh. Scratched your baby up pretty bad.] Sorry, V.
jl_1677043911795367936  Now I go back, find Misty[ and we do somethin' to make me feel alive again.]
jl_1834500545020096512  C'mon, let's go have some lunch.   (already in noodle tree)
jl_1885122683250601984  Uh, I ain't gonna lie... I'm a bit light. I can't pay you now.  (date 1)
jl_2028600518010400768  Come on, chica. You know I was raised right.   (date 3 — who pays)
jl_1721401856077123596  Two Tequila Old Fashioneds with a splash of cerveza and a chili garnish.
jl_1721408614996692992  A Tequila Old Fashioned with a splash of cerveza and a chili garnish.  (singular variant)
jl_1660742685327118336  Yeah, partner. We'll go halfsies.
jl_1658860298971172864  [But that's done after tomorrow.] Afterlife, here we come, baby! Yeah!  (afterlife date accept)
```
