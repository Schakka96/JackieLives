# Casting sheet — "Ghost in the Machine" (Parts 1-5)

_Written 2026-08-25. Source: `vo_library/jackie.csv` (1101 rows, header
`id,text,text_male,seconds,to,context,expression,uses,scenes`). Cross-referenced against
`tools/v_index.py` (V's 12,996-line corpus) and the `jl_<id>` references already burned into
`mod/JackieLives/*.lua`. Every ID below is copied verbatim from the CSV as a string — never
retype or reformat one; String IDs are ~2e18 and silently corrupt if they touch a Lua/JSON
number type._

## 0. How to read this

- **id** — String ID, exact string from `jackie.csv`, column 1.
- **text** — verbatim `text` column. Rows wrapped in `<mothertongue .../>` or `<kiroshi .../>`
  are Spanish-language takes; `t="..."` / the text after `a="..."` is the English subtitle CDPR
  shipped — quote the whole tag as-is when wiring it into Lua (see existing `retrieval.lua` usage),
  don't hand-simplify it.
- **s** — duration in seconds (`seconds` column).
- **to** — addressee column as recorded (mostly `V`; blank or `jackie`/`misty`/`claire` for a
  handful — these are base-game combat/dialogue barks, so "to=jackie" sometimes means the line
  was originally aimed *at* Jackie by someone else in that scene, not that Jackie is talking to
  himself; treat `to` as a hint, not gospel).
- **used?** — `YES` if this exact String ID already appears as `jl_<id>` somewhere in
  `mod/JackieLives/*.lua` (see §6). A `YES` line can usually still be reused elsewhere in the UI
  (nothing stops two menus from playing the same clip) but reusing it *inside the new questline
  too* risks the player hearing the identical clip twice in close succession — flagged so the
  writer can choose deliberately, not by accident.

Bold rows are the strongest picks per category.

---

## 1. Deflection — "I'm fine, don't worry about it"

Thin. Only 7 candidates matched at all, and most aren't really deflection so much as adjacent
phrases ("just biz," "don't worry"). This is the single worst-served category for Part 1 beat 1
("he shrugs it off with a real line").

| id | text | s | to | used? | note |
|---|---|---|---|---|---|
| **1725480866495123456** | "Don't worry, got this." | 2.249 | — | | **best fit for the post-episode shrug-off** — short, generic, no plot hook |
| **1690852006870765568** | "She'll be back in a sec, don't worry." | 2.801 | — | | needs a rewrite of context around "she" or use as a stand-in template for cadence only |
| 1722551390467575808 | "Just biz, no big deal." | 2.218 | claire | | addressed to Claire in the original scene — reuse is a stretch but the line reads clean |
| 1834361465607221248 | "Nothin' personal, [compa]. Just biz." | 3.386 | V | | mothertongue tag, has "compa" — usable as V-directed brush-off |
| 1732910034719797248 | "Cause I got this feelin' you got a lotta time... an' nothin' to spend it on." | 4.822 | V | | too specific/bantery, weak fit |
| 2008326330108538880 / 1866205008628969472 | "Listen, [chica/amiga], I got this thing. Mind if I borrow your wheels?" | ~4.7-6.9 | V | | wrong topic (borrowing a car), not usable as-is |

**Constraint:** there is no line where Jackie explicitly says a version of "I'm fine" in plain
English. Every "fine" hit in the corpus is either Spanish-tagged anger ("Fine, have it your way!")
or unrelated. Write Part 1 beat 1 around **1725480866495123456** ("Don't worry, got this") — it's
the closest the library gets to a genuine brush-off.

---

## 2. Pain / physical distress / exertion / grunts

The deepest category by far (59 raw hits; combat VO is what Jackie recorded most of). Curated to
the cleanest content-free (non-plot-locked) grunts and pain reads.

| id | text | s | to | used? | note |
|---|---|---|---|---|---|
| **2014500975731875864** | "Argh… I'm leakin' a little…" | 5.327 | V | | direct admission of being hit — strong for Part 1 episode or Part 3 escalation |
| **1888115393428475904** | "Agh. Scratched your baby up pretty bad. Sorry, V." | 5.315 | V | | car-specific, skip unless a vehicle beat exists |
| **1624421744111398912** | "Wait for you by the elevators. Ugh, this little bastard's heavier than I thought." | 6.019 | V | | plot-locked (elevators/heist), skip |
| **1638689384933675008** | "Hah--... agh! Heh, hng..." | 3.629 | V | | pure non-verbal distress, no plot hook — **excellent for the mid-follow spasm/glitch beat**, plays clean as a stumble reaction |
| **1678035821641031680** | "Agh, I dunno..." | 1.654 | V | | short, standalone, usable as post-glitch confusion |
| **1741832357434814464** | "Agh, don't thrill you, that?" | 2.302 | V | | standalone-ish, could work as gallows-humor recovery line |
| **1208276870125637632** | "Heads up! Aaaaaargh!" | 4.031 | V | | combat-flavored pain cry, good for the takeover/weapon-discharge beat in Part 3 |
| **1926923970895048704** | "Ay, had to hurt… Shoulda followed orders." | 2.31 | V | | standalone, self-deprecating pain line |
| **2238165716145709064** | "Cover, V! You're hurt!" | 1.882 | jackie | | combat callout, addressee reversed (someone telling V) — usable in a fight scene, not a solo beat |
| 1793962760102408192 | mothertongue: "Job's gonna kill you." | 3.329 | V | | thematically perfect line for foreshadowing but plot-tagged to a specific job — usable almost verbatim as gallows humor about the arc itself |
| 1660275126094024704 | "Ugh. What a fat-ass." | 3.11 | V | | comic, not usable for a pain beat |
| **1225494768812494848** | "Can't hurt to try." | 1.736 | V | | double meaning available ("hurt") — good deflection-adjacent line too |

**Best picks for the Part 1 "hand spasms / glitch" beat:** 1638689384933675008 (pure non-verbal
distress, no plot lock) as the glitch grunt, followed by 1678035821641031680 ("Agh, I dunno...")
as the "he shrugs it off" recovery — this is a two-line combo that reads as a stumble-and-recover
without any editing.

---

## 3. Fear / admitting fear / vulnerability

**Critical finding — flag for §4.** There is **no line in the corpus that contains the words
"afraid" or "scared"** (checked with `grep -in "afraid\|scared\|terrified\|frightened"
vo_library/jackie.csv` — zero hits). QUEST_ARASAKA.md §3 Part 3 explicitly says Jackie's fear
admission at the end of Part 3 uses "his own voice, because the library has that take." **That
take does not exist.** See §4 below — this is the single biggest writing constraint in the whole
document.

What exists instead is "worried," always about *him* being worried for someone else, or someone
else being worried *about him* — never Jackie naming his own fear:

| id | text | s | to | used? | note |
|---|---|---|---|---|---|
| 2028635009449914368 | "Worried 'bout me. Been for a while." | 4.299 | V | | closest available thing — Jackie relaying that *someone else* (implicitly Misty) is worried about him. Usable as a deflected, third-person way of admitting something's wrong |
| 1795303424698900480 | "Ehhh, y'know. She's worried about me – whatever." | 5.178 | V | | same pattern — brush-off around someone else's worry, good Part 1/3 texture |
| 1866271332487032832 | "Uh-huh. Gonna be worried sick if I don't show." | 3.824 | — | | about Misty worrying if he's late — reusable for the "don't tell Misty" SMS beat's tension |
| 1660215901783347200 | "Oh, was worried I'd have to turn to farming... sure hope you're here for me." | 6.201 | V | | closest first-person "worried" but comic/plot-specific (Panam content) — weak fit |
| 1764807613009883148 | "Worry about me later! Check the Relic!" | 4.003 | V | | plot-locked to the Relic, not reusable verbatim, but the SHAPE ("worry about me later") is a usable deflection pattern for Part 1 |

**Recommendation:** do not attempt a literal "I'm afraid" VO moment. Write the Part 3 fear beat as
**text** (SMS, per the mod's own "voice for what Jackie can really say, text for everything else"
rule) and reserve 2028635009449914368 / 1795303424698900480 for a *voiced* moment where Jackie
talks about Misty worrying — the closest the corpus gets to him admitting something's wrong, at
one remove.

---

## 4. Anger, threats, combat callouts, "they came for me"

Strong category — this is what Jackie's combat VO is largely made of, good for Part 2's snatch-
squad fights.

| id | text | s | to | used? | note |
|---|---|---|---|---|---|
| **1671130383003639808** | "I hate these 'borg fuckers. Just had to be them…" | 4.789 | V | | good generic corp-goon hate line, works for an Arasaka squad fight |
| **1653073643632050176** | "OK, V, flank him and draw his fire! I'll do the rest!" | 5.117 | V | | tactical callout, perfect for the snatch-squad fight assembly |
| **1679805962162757648** | "Soon as somethin' seems not right, light 'em up." | 3.388 | V | | good pre-fight tension line, could open the drone/Mid-heat beat |
| **1861972099194613760** | "Jesus, these fuckers move fast!" | 3.009 | V | | generic combat reaction, reusable anywhere |
| 2238744397675143176 | "Watch it, V. They got cams." | 2.451 | jackie | | **very on-theme for the beacon/surveillance thread** — "they got cams" reads naturally as paranoia about being watched |
| **YES** — 1679806464288055296 | "Got me right behind you." | 2.269 | jackie | YES | already used (retrieval.lua talkLines area) — avoid stacking in the same scene |
| 2238685622691864584 | "I'm empty! Need to reload!" | 1.937 | jackie | | pure combat bark, reusable in any Part 2/4/5 firefight |
| 2238165104918175752 | "V, watch it!" | 1.87 | jackie | | generic combat callout |
| 2238685622758973440 | "Hang on! Reloadin'!" | 1.627 | jackie | | combat bark |
| 2257914255984926728 | "Come on, motherfuckers!" | 1.545 | jackie | | aggression bark, good for the Part 5C raid set-piece |
| 2238682834201124868 | "Cover me, V!" | 1.335 | jackie | | combat bark |
| 2238685622607978504 | "Gotta reload!" | 1.237 | jackie | | combat bark |
| 1616176656287490048 | mothertongue: "Eat my balls motherfuckers!" | 4.178 | V | | flavor line for the Part 5C raid — high energy |
| **YES** — 1625819953367019520 | "It's the biz, V. Everyone's got blood on their hands. You deal with it, you move on." | 6.862 | V | YES | already used — thematically very strong for Part 1/3 (the "I chose this life" argument) but reusing risks repetition; consider it "spent" |

**No line explicitly says "they came for me."** Closest available text is "watch it, V, they got
cams" (surveillance-flavored) and the generic combat barks above — the *naming* of "they're after
me specifically" has to be carried by an SMS or journal entry per Part 2 beat 1 ("he's the one who
says out loud that they came for him"), because no single VO line does that job cleanly. Flag for
§4 below.

---

## 5. Gratitude, affection, thanks to V

**Very thin — 6 hits total, and only 2 are genuinely gratitude-to-V in English.**

| id | text | s | to | used? | note |
|---|---|---|---|---|---|
| **1866254590956171264** | "Aah, savin' my ass, V, thank you. How about I drive you home, eh?" | 5.849 | V | | **the strongest gratitude line in the whole corpus** — direct thanks to V, plot-light, usable almost anywhere in Parts 2-4 |
| **1993514843414274048** | "Thanks, I will! V, you take it easy, OK? Rest up a bit." | 6.925 | V | | genuinely warm, good closing beat for a "V looked after him" moment (Part 3 dinner or Part 4 aftermath) |
| YES — 1255773314399088640 | "Ah, thanks, Misty. You're the best." | 4.036 | misty | YES | thanks *Misty*, not V — already used, and wrong addressee for a V-directed beat |
| 1883849269254066176 | mothertongue: "Thanks, babe." | 1.82 | V | | short, works as a quick aside but generic |
| 1702388203143352320 | mothertongue: "Love you too, Ma." | 1.838 | jackie | | addressed within a Mama-call context, not reusable for V |
| 1567641019241091072 | "Thank God. I'm stuffed!" | 3.269 | V | | comic, food context — not usable |

**Constraint:** the corpus has essentially **two** real V-directed gratitude/affection lines
(1866254590956171264 and 1993514843414274048). Budget them carefully — do not spend both early;
1866254590956171264 is strong enough to anchor Part 4's aftermath regardless of ending.

---

## 6. Agreement / "let's go" / "on my way" / meeting up

Well served — Jackie has a lot of logistics VO from being a companion NPC already.

| id | text | s | to | used? | note |
|---|---|---|---|---|---|
| **1671091734673317888** | "Well, whatever. Let's go get this tech. You scheme yet? You got a plan?" | 6.49 | V | | plot-general enough to reuse for "let's go deal with the beacon" |
| YES — 1623208923512107008 | "OK, lemme take ya. I brought your ride. Yeah, throw on some threads, meet me downstairs." | 6.263 | V | YES | already in retrieval.lua's talkLines — good template, reuse text pattern not the clip |
| **2259031306614972424** | "V, there's time for thinkin', time for gettin' the fuck out! Let's go!" | 5.608 | jackie | | high-urgency — perfect for the Part 2 snatch-squad "get out now" beat |
| YES — 1691270077089771520 | "That kinda sounded like a 'yes.' Meet me at Lizzie's. Be there in an hour." | 5.388 | V | YES | already used for the pick-a-spot mechanic |
| 1989698664761466896 | "All right, 'Hannah,' let's go." | 3.481 | V | | has a proper noun ("Hannah") — plot-locked, skip |
| 1687435597683843072 | "Oof, good. It's movin', let's go." | 3.041 | V | | generic, reusable |
| YES — 1834500545020096512 | "C'mon, let's go have some lunch." | 2.939 | V | | already used |
| YES — 1762127358882361344 | "So let's do our thing." | 2.134 | V | YES | already used (retrieval.lua) |
| YES — 2239013722221887488 | "Ready to mosey?" | 1.867 | V | YES | already used |
| 872106507270864912 | "Let's go!" | 1.828 | jackie | | short, generic, unspent |
| 1688508282677452800 | mothertongue: "Let's go already." | 1.396 | V | | short, unspent |
| 2238069786960633864 | "Let's goooo!" | 0.999 | — | | punchy, good for a chase/fight |

**Strong category — the constraint here is the opposite of most others: plenty of unspent
material** (2259031306614972424, 1687435597683843072, 872106507270864912,
1688508282677452800, 2238069786960633864 are all currently unused in the mod).

---

## 7. Money, gigs, work talk

Adequate for Part 3's "one more job" beat.

| id | text | s | to | used? | note |
|---|---|---|---|---|---|
| **1912747430187790336** | "It's always the same story. You land on fresh turf, local fixer waves his dick around, but... he's smilin' – sayin' you'll be up to your neck in gigs and eddies." | 9.643 | V | | good scene-setter for "one more job" — generic fixer talk |
| **1802689463280660480** | "Won't come cheap. And it'll have to be done on the sly — no trail, hard eddies only." | 6.168 | jackie | | **excellent for Part 3's "the money" beat** — reads directly as talking about paying for the black-market chrome operation |
| 1896561141189079040 | "Oh, almost forgot. Should get Wakako on the holo – tell her the job's done." | 5.809 | V | | Wakako-specific, usable if the "one gig" fixer is Wakako |
| 1802719692602667008 | "Umh. Least you still got the eddies for the hitjob." | 4.228 | V | | generic enough to repurpose |
| 1660505895391481856 | "'Course I do. What, the fixer didn't give you the job detes?" | 3.913 | V | | generic fixer/gig banter |
| 1796850462489505792 | "Got sparks flyin' between the Valentino boys and Maelstrom. Eddies there for the takin'... as long as ya don't get flatlined." | 8.21 | V | | plot-specific (Valentinos/Maelstrom), skip unless reusing that gang |
| 1722898438958141456 | "So, not to count chickens, but when'll we see our eddies?" | 3.638 | — | | good closer for a gig-payout scene |

---

## 8. Family: Mama, Misty, Vik mentions

Misty is well covered (15 raw hits, most reused-worthy); Vik and Mama are scarce — a real
constraint for a series that leans on both.

**Misty (best of 15):**

| id | text | s | to | used? | note |
|---|---|---|---|---|---|
| **1638691848869171208** | "Misty… She knew… She always knew…" | 12.128 | V | | powerful, but check `scenes` — likely plot-tagged to the base game's ending; verify before reuse to avoid spoiler bleed |
| YES — 2024290835469197312 | "Misty knew... Misty always knows..." | 4.176 | V | YES | shorter variant, already used |
| **1794044297741217792** | "Misty asked me… not to take this job." | 4.209 | V | | **direct fit for Part 3's "one more job"** — Misty's objection is already voiced |
| YES — 1677043911795367936 | "Now I go back, find Misty and we do somethin' to make me feel alive again." | 5.685 | V | YES | already used |
| 1790882350032015360 | "Could bring Misty here one day. When we, uh... close this deal." | 4.941 | V | | usable for Part 5A epilogue setup |
| 2008326252916568064 | "Oh, Misty..." | 2.564 | V | | short, tone-neutral, flexible |
| 1614041695221669888 | "I'll sit tight over here. Me 'n' Misty got a little catchin' up to do." | 4.362 | V | | good for a "date with Misty" beat, low plot lock |

**Vik — only 3 hits in the entire corpus, none currently used:**

| id | text | s | to | note |
|---|---|---|---|---|
| **1875104239217438720** | "Find me once Vik's done dustin' your circuits. We'll hash out what Dex's cooked up for us." | 8.028 | V | Dex reference is plot-locked to the heist prep — usable only if trimmed/context-hidden |
| **1661848757298057216** | "Unlike someone, I haven't run up my tab with Vik. Got last-gen firmware, low flow." | 5.76 | V | **best Vik-adjacent line for Part 1's "at Vik's" objective** — self-contained, references his relationship with Vik without a specific plot hook |
| 1614108004497641472 | "Oh, was supposed to stop by Vik's anyhow. I got a date – me and Misty." | 5.62 | V | usable as a light connective line ("heading to Vik's") for the Part 1 objective |

**Mama — only 2 genuine hits (2 others are unrelated "mamá"/"mamacita" Spanish fillers):**

| id | text | s | to | note |
|---|---|---|---|---|
| **1625680459640795136** | "Noodles – check. Synthsirloin – check. ... you're lookin' at Mama Welles' signature sopa de fideos, hahah!" | 10.588 | V | the only real Mama Welles reference with texture — good for Part 5A's dinner-table epilogue |
| 1917219479049138176 | "Haha, you would not believe my mama's chili – best in town." | 5.107 | V | second Mama reference, chili detail matches Part 5A's "dinner system" |

**Constraint:** Vik and Mama both have only 2-3 usable lines total across the entire 1101-line
corpus. Any scene that needs Jackie to talk *about* Vik or Mama at length has almost nothing to
draw on — this pushes those beats toward SMS/journal text (consistent with the mod's own rule)
rather than voiced dialogue.

---

## 9. Arasaka / corpo / heist / Konpeki mentions

Good depth (15 hits) — this is base-game heist VO, directly reusable for flashback-flavored lines
in Parts 1-2.

| id | text | s | to | used? | note |
|---|---|---|---|---|---|
| **1785258183320547328** | "Saburo-fuckin'- Arasaka's dead. Feels weird to even say it." | 6.601 | V | | strong reflective line, good for a Part 1/2 flashback beat |
| YES — 1783599541039017984 | mothertongue: "Old man Arasaka's AV should still be parked on the roof." | 5.131 | V | YES | already used |
| 1761838731224821760 | "Old man Arasaka – he never left... His AVs gotta be on the roof still, right?" | 6.116 | V | | longer variant of the used line above, unspent, could stand in for it elsewhere |
| 1904018262013562880 | "Un-fucking-believable… Saburo Arasaka." | 4.807 | jackie | | short reaction line, reusable for reveal beats |
| 1993485821649166336 | "Yorinobu Arasaka. The good life, I mean." | 4.303 | V | | usable for corpo-life commentary, thematically apt for the beacon thread |
| 2259019791086231552 | "Hurry up! Yorinobu could be back any second!" | 3.457 | jackie | | urgency bark, could be repurposed for a snatch-squad chase (swap "Yorinobu" mentally, subtitle carries the real meaning) |
| 1695238636118417408 | "The Relic!" | 1.362 | V | | plot-locked to the Relic specifically, skip |
| 1764807613009883148 | "Worry about me later! Check the Relic!" | 4.003 | V | | plot-locked, skip unless reusing Relic beats |

**No line mentions the beacon, the daemon, a netrunner, Nix, or a snatch squad by name** — those
are all Part 2-3 inventions with zero VO support, exactly as QUEST_ARASAKA.md already assumes
(they're meant to be carried by Nix's shard/SMS channel). Confirmed by grep: 0 hits for
"surveillance," "netrunner," "daemon," "hack," or "Nix" anywhere in `jackie.csv`.

---

## 10. Goodbye / farewell / something that could close an arc

**Thin and repetitive — 8 hits, almost all the same "Ahí luego, V" Spanish farewell, and 6 of the
8 are already used** (this is the pool `retrieval.lua`'s `partingSfx`/`farewellPool` already
drains — see §11).

| id | text | s | to | used? | note |
|---|---|---|---|---|---|
| 1754957630472646704 | mothertongue: "Ahí luego. Don't forget to let Dex know we got his toy for him." | 4.941 | V | | longer variant, has a Dex plot hook — trim if reused |
| 1866291879677685760 | mothertongue: "Ahí luego. I will." | 2.597 | V | | unspent, generic, safe to use in a new scene |
| YES (x6) | "Ahí luego, V." / "Hasta luego." / "Make moves, [chica]." variants | 1.0-2.0 | V/— | YES | already the entire farewell pool in retrieval.lua |

**Constraint — this is the second-biggest gap after the fear line.** There is **no emotionally
weighty farewell/closure line** anywhere in the corpus — nothing like "take care of yourself" or
"this meant something" or "I'm glad I made it." Every farewell take is a casual, repeatable
"see ya" built for a companion who's about to be seen again in five minutes, not for closing a
five-part arc. **Part 5's epilogues cannot be carried by a single climactic VO line** — they have
to be carried by staging (Mama's table, the maintenance ritual, the raid) with ordinary
"Ahí luego"-style lines underneath, not a written "goodbye" moment.

---

## 11. Chrome, ripperdoc, being hurt, dying, hospital

Adequate for Part 1's Vik-scan beat and Part 3's medical stakes.

| id | text | s | to | used? | note |
|---|---|---|---|---|---|
| **1861942814782189568** | "Hey, hey, should I get you to a ripper?" | 4.56 | V | | **directly usable, near-verbatim, for Part 1's "take Jackie to Vik" prompt** — he's asking about a ripper for V, but the shape/phrase is exactly right and could be echoed back |
| **1705592372028665856** | "First stop – ripperdoc?" | 2.959 | V | | short, clean, plot-free — good connective line for the Part 1 objective |
| 1711253382494904320 | "Tech poetry. Great piece of chrome. Feels like fucking Christmas morning. Hahaha." | 7.926 | V | | tonally wrong (celebratory) for the reveal scene, but useful for contrast earlier in the arc (Jackie liking chrome before he learns what's inside him) |
| 1995110640862031872 | "He's fuckin' whacked somethin' special. Junkies snort junk, Royce snorts chrome." | 6.545 | V | | Royce-specific plot lock, skip |
| 1141879035126288384 | "She's flatlinin'!" | 1.621 | V | | pronoun mismatch ("she"), not directly reusable, but confirms "flatlinin'" is in his vocabulary for a Part 3 crisis beat elsewhere if a matching take turns up |
| 1163336923027804160 | "Ehh, gear from the jacked convoy, gotta be... Must've been all over it like maggots on dead meat." | 7.05 | V | | plot-locked to a specific convoy, skip |

**No line uses the words "dying," "died," "hospital," "surgery," or "implant."** The corpus
covers "chrome" and "ripperdoc" fine but has nothing for the more clinical/mortal register Part 3
needs when Vik explains the operation risk — that has to be text (the shard, per the mod's own
design rule) rather than voiced Jackie dialogue, since Jackie himself never recorded a line in
that register.

---

## 4. Beats with NO usable Jackie VO — design constraints

Cross-checking QUEST_ARASAKA.md §3 against the corpus, four beats have **no supporting line at
all** and must be carried by text (SMS/shard/journal), exactly as the document's own "voice for
what Jackie can really say, text for everything else" rule already anticipates — but these are
worth naming explicitly so the writer doesn't go looking for a take that isn't there:

1. **Part 1 beat 1 — "he shrugs it off with a real line."** No plain-English "I'm fine" line
   exists (§1). Best substitute: 1725480866495123456 ("Don't worry, got this"), which is close
   but not a perfect match — the writer should accept it rather than search further.
2. **Part 2 beat 1 — "he's the one who says out loud that they came for him."** No line contains
   "they came for me" or names a snatch squad/surveillance/beacon (§4, §9). Closest is
   2238744397675143176 ("Watch it, V. They got cams") — usable as a *lead-in* line, but the actual
   naming of the threat has to land in an SMS, matching the mod's existing pattern.
3. **Part 3 end — "Jackie is afraid, and says so once, in his own voice, because the library has
   that take."** **This is false — the take does not exist.** Zero hits for
   afraid/scared/terrified/frightened anywhere in `jackie.csv` (§3). This line in
   QUEST_ARASAKA.md needs to be corrected or the beat needs to be re-cast as text (an SMS
   admission) with a *voiced* echo using one of the "worried" lines in §3 instead of a direct fear
   admission.
4. **Part 5 epilogues — any single line meant to feel like the arc's emotional close.** The
   farewell pool is uniformly casual and already mostly spent (§10). Epilogues need to be carried
   by staging + existing systems (dinner, ritual, raid), not a new "big" VO moment.

Everything else QUEST_ARASAKA.md asks for (heat-system flavor barks, snatch-squad combat VO, the
Vik-scan objective line, the money/gig beat, Misty's "asked me not to take this job") has at least
one real, usable candidate above.

---

## 5. Reuse collisions — String IDs already burned into the mod

`grep -ohE 'jl_[0-9]{15,}' mod/JackieLives/*.lua | sort -u` finds **127** distinct `jl_<id>`
references across the Lua source (this pattern — `sfx = "jl_<id>"` — is how the mod actually plays
a line; raw quoted numeric IDs elsewhere, e.g. in `vo_durations.lua`'s 140-entry duration table,
are a duration lookup, not a "spoken in the game" list, and were excluded from this count). Of
those 127, **84 IDs belong to Jackie's own corpus** (the remaining 43 are V lines, mostly in
`vo_female_ids.lua`/`vo_gender.lua`).

Files carrying Jackie IDs, by count:

| file | Jackie IDs referenced |
|---|---|
| `retrieval.lua` | the bulk — talkLines pool, farewellPool, "let's go" pool, dialogue pick lines |
| `config.lua` | 0 raw quoted IDs (all its VO goes through `sfx = "jl_..."` inside table literals counted above) |
| `vo_gender.lua` | 6 |
| `vo_female_ids.lua` | 98 (mostly female-V-voice line-selection map, not story dialogue) |
| `init.lua` | 1 |

The categories above mark every already-used ID as `YES` inline. **Highest-risk collision zone is
§6 (agreement/let's-go) and §10 (goodbye)** — those are exactly the pools `retrieval.lua` already
drains for its own "let's go"/farewell mechanics, so the new questline should prefer the *unspent*
alternatives listed in each table rather than re-firing a clip the player has already heard dozens
of times in normal companion play.

---

## Method note

Categories were built by regex sweep over the `text` column (case-insensitive, covering plain
English plus the `t="..."`/`a="..."` fragments inside `<mothertongue>`/`<kiroshi>` tags), manually
reviewed and pruned per category rather than dumped wholesale. "Used" status was computed by
grepping `mod/JackieLives/*.lua` for the literal `jl_<id>` pattern that `vo.lua` requires for
playback, cross-referenced against `jackie.csv`'s ID column. No V lines are tabled here — v_index.py
is best used per-scene once the questline's actual dialogue choices are drafted, since V's fit
depends on channel/mood/addressee axes that don't map cleanly onto Jackie's smaller, flatter
corpus; flag if a follow-up V-line pass is wanted once Part 1's dialogue tree is drafted.
