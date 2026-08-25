--[[
  sidequests.lua — the Heywood jobs.  JackieLives 2.0                         (v2.0-a1)
  ============================================================================================
  Nine small quests, same schema as `storyboard.lua` (read that file's header first — it defines
  every field used here). These are NOT filler between the acts of "Ghost in the Machine". They
  do three specific jobs, and every one of them is deliberate:

    1. THEY PLANT THE ARC'S PAYOFFS. A gun on the mantelpiece in Act I has to be put there by
       somebody. Five of these nine quests exist so that a moment in Parts 3-5 has something to
       detonate — the bike, the kid, the plate, the card, the wall. Play none of them and the arc
       still works; play them and the ending is about things you did.
    2. THEY ARE THE ONLY PLACE THIS MOD IS FUNNY. The main arc is a man losing control of his
       hands. Without relief it is unbearable by Part 3 — and, more practically, a player who has
       laughed with Jackie in a noodle-stand argument has more to lose in Part 4 than one who has
       only watched him deteriorate. The comedy is load-bearing. Do not cut it for tone.
    3. THEY SHOW THE LIFE HE CHOSE. The premise of this whole mod is that Jackie walked away from
       the merc life and became a neighbourhood fixer. That claim has been an assertion in a
       design doc for two years. These quests are it actually happening: small debts, family
       favours, bar disputes, a kid he won't break.

  PLACEMENT. Each quest declares `slot`:
      "anytime"       available whenever the mod is unlocked
      "before:<part>" only offered before that part of the arc arms — because it stops making
                      sense once he is visibly ill
      "between:a,b"   the mod actively OFFERS it in that gap, as pacing relief
      "arc:<beat>"    story-locked; it belongs to the arc and only appears there
  The offer system never nags: one SMS, and then it waits in his talk options forever.

  COST. Every quest here is assembled from systems that already ship — the summon, the follow,
  the venue schedule, the dinner outing, the dialogue widget, the spawn-and-fight pattern, SMS,
  and shards. There is no new engine in this file. That is why nine of them is realistic.
--]]

local M = {}

M.VERSION = "2.0-a1"

M.quests = {

-- =============================================================================================
{ id = "side_bike", title = "The Arch", slot = "anytime", length = "15 min",
  logline = "V has been carrying the keys to a dead man's motorcycle for a year. He isn't dead.",
  intent = "The first side quest anyone should play, because it is the one that hurts in the "
        .. "cheapest way: nothing happens in it. There is no fight, no fixer, no eddies. There is "
        .. "a set of keys in V's inventory that the game gave them as a memorial, and a man "
        .. "standing in front of them who is not memorialised. The mod has had 'his bike' sitting "
        .. "in the design doc as a TODO since 2024 (DESIGN.md §10.5). This is it.",
  plants = "The Arch itself. Part 5C's escape is on this bike; Part 5A is him handing the keys "
        .. "back for good, which is the quietest way the mod has of saying he knows what he is now.",
  -- NOT gated on an inventory item: vanilla 2.x has no bike-"key" object (config.lua's
  -- `bikeReturn.keyItem` is commented out for exactly this reason). It gates on the mod's own
  -- bike-return fact instead — 0 means V still has the Arch, which is the state this quest is about.
  arms = { stage = 4, familiarity = 0, factIsZero = "jackielives_bikeback" },
  beats = {
    { id = "bike_sms", kind = "sms",
      sms = { thread = "jackie", id = "side_bike_open",
        messages = {
          { from = "jackie", text = "hey" },
          { from = "jackie", text = "so this is gonna sound weird" },
          { from = "jackie", text = "my ma gave you my keys huh" },
          { from = "jackie", text = "she does that. she gave my cousin my jacket and he's got a foot on me" },
        },
        replies = {
          { id = "yes",  text = "She did. It's parked. It's clean. It's yours." },
          { id = "keep", text = "Finders keepers, Welles." },
        },
        followups = {
          yes  = { { from = "jackie", text = "…" }, { from = "jackie", text = "el coyote. tonight." } },
          keep = { { from = "jackie", text = "HA" }, { from = "jackie", text = "you're gonna give it back and we both know it" }, { from = "jackie", text = "el coyote. tonight." } },
        } } },
    { id = "bike_handover", kind = "scene", place = "coyote", window = { 20.0, 26.0 },
      intent = "He does not take them. He looks at them on the bar for a while and says the bike "
            .. "was never really his either — he was still paying it off when he 'died', and "
            .. "somebody at the dealership has presumably written him a very confused letter. "
            .. "Then he takes them. Comedy first, weight second, in that order, always.",
      vo = { open = "lets_go", close = "thanks_v" },
      choices = {
        { id = "give",  text = "[Hand over the keys]",     sets = { jackielives_side_bike = 1 } },
        { id = "share", text = "Keep it at mine. You ride it whenever.",
          outcome = "He agrees far too fast. He does not want it parked outside Mama's where she "
                 .. "has to look at it.", sets = { jackielives_side_bike = 2 } },
      } },
  },
},

-- =============================================================================================
{ id = "side_wall", title = "Last Rites", slot = "before:p3", length = "20 min",
  logline = "Somebody keeps lighting candles under Jackie Welles' name.",
  intent = "The heaviest of the side quests and the one that earns Part 4's best line. Heywood "
        .. "put him on a memorial wall. The candles are still being replaced by a woman on his "
        .. "street who does not know and would not believe it. He goes at 3am so nobody sees him. "
        .. "Structurally this is a HORROR image played completely straight — a man reading his own "
        .. "name — and the mod should not comment on it. No music, no dialogue for the first "
        .. "thirty seconds. Let the player stand there.",
  plants = "Part 4: 'I already got a wall, mano. Don't put me on it twice.' Do not use that line "
        .. "anywhere else, and do not use it at all if this quest was never played — a callback "
        .. "to nothing is worse than no callback.",
  arms = { stage = 4, familiarity = 2, arcBefore = 3 },
  beats = {
    { id = "wall_sms", kind = "sms",
      sms = { thread = "jackie", id = "side_wall_open",
        messages = {
          { from = "jackie", text = "you busy at 3" },
          { from = "jackie", text = "3am i mean" },
          { from = "jackie", text = "don't ask" },
        },
        replies = { { id = "yes", text = "I'll be there." }, { id = "why", text = "Jackie. Ask what?" } },
        followups = { yes = { { from = "jackie", text = "vista del rey. the wall by the laundromat" } },
                      why = { { from = "jackie", text = "vista del rey. the wall by the laundromat" },
                              { from = "jackie", text = "you'll get it when you see it" } } } } },
    { id = "wall_visit", kind = "scene", place = "wall", window = { 2.0, 5.0 },
      actors = { "jackie" },
      script = { "no VO for 30s", "his name is on the wall, painted, with the date",
                 "fresh candles — someone lit them tonight", "he crouches and puts one out, then relights it" },
      vo = { after = "deflect_hard" },
      choices = {
        { id = "sorry",  text = "I should've told them. All of them.",
          outcome = "'Nah. Would've made it worse.' He is wrong and they both know it.", familiarity = 3 },
        { id = "who",    text = "Who's lighting them?",
          outcome = "Señora Ruiz, four doors down, every Sunday for a year. He has been avoiding "
                 .. "her street. This is the detail that makes the wall real." },
        { id = "silent", text = "[Say nothing]",
          outcome = "The best option and the mod should not tell the player that.", familiarity = 3 },
      },
      sets = { jackielives_side_wall = 1 } },
  },
},

-- =============================================================================================
{ id = "side_rico", title = "Padre's Favour", slot = "before:p3", length = "25 min",
  logline = "A Valentino kid owes money to people who break fingers. Jackie has been sent to break them.",
  intent = "The quest that proves what 'community fixer' means, by showing the job Jackie will "
        .. "NOT do. Padre asks him to collect; he goes, finds a nineteen-year-old, and pays the "
        .. "debt himself out of money he does not have. That is the character thesis of the whole "
        .. "mod delivered in one action instead of a paragraph — and it sets up Part 3's money "
        .. "problem with a reason he is broke that is entirely to his credit.",
  plants = "Rico. He is the kid in the room during Part 3's takeover, which is what makes that "
        .. "beat unbearable rather than merely alarming — and he is the one who turns up with "
        .. "four Valentinos in Part 5C, uninvited, because Jackie once decided not to hurt him.",
  arms = { stage = 4, familiarity = 1, arcBefore = 3 },
  beats = {
    { id = "rico_call", kind = "sms",
      sms = { thread = "jackie", id = "side_rico_open",
        messages = {
          { from = "jackie", text = "padre's got somethin for me and i don't like the shape of it" },
          { from = "jackie", text = "come with? i'd rather have a witness" },
        },
        replies = { { id = "yes", text = "Where?" }, { id = "no", text = "That's a bad idea, Jackie." } },
        followups = { yes = { { from = "jackie", text = "arroyo. bring nothin loud" } },
                      no  = { { from = "jackie", text = "yeah" }, { from = "jackie", text = "come anyway" } } } } },
    { id = "rico_find", kind = "travel", place = "gig_lot", window = { 16.0, 24.0 },
      journal = { quest = "side_rico", phase = "main", objective = "find_the_kid", text = "Find the debtor" } },
    { id = "rico_choice", kind = "choice",
      intent = "V's choice, not Jackie's — because the mod should occasionally let the player be "
            .. "the one who decides who Jackie gets to be. If V insists on collecting, he does it, "
            .. "and he is quiet for two in-game days afterwards, and that is the whole punishment. "
            .. "No fail state, no lecture.",
      choices = {
        { id = "pay",     text = "[Pay the kid's debt — €$2,000]", cost = 2000,
          outcome = "Jackie pays half before V can finish the sentence. He was always going to.",
          sets = { jackielives_side_rico = 1 }, familiarity = 4 },
        { id = "lean",    text = "Scare him. Don't touch him.",
          outcome = "Works. Jackie hates it. Rico remembers V's face, not Jackie's.",
          sets = { jackielives_side_rico = 2 } },
        { id = "collect", text = "Padre asked for fingers.",
          outcome = "He does it, and he doesn't argue, and he doesn't look at V for two days.",
          sets = { jackielives_side_rico = 0 }, familiarity = -6 },
      } },
  },
},

-- =============================================================================================
{ id = "side_dinner", title = "Mama's Errand", slot = "anytime", length = "20 min",
  logline = "Nine items. One shopping list. Two grown men who cannot follow it.",
  intent = "Pure comedy, and the mod's warmest twenty minutes. Mama sends them for ingredients; "
        .. "the list is in Spanish; Jackie cannot read his mother's handwriting; they buy the "
        .. "wrong chillies twice. It ends at her table. Every serious mod needs one quest whose "
        .. "only stake is a sauce, and this is that quest — but it is also where the arc's saddest "
        .. "prop gets established, and the player will not notice it going in.",
  plants = "The plate. Mama lays one for Jackie every week and has since the funeral; here it "
        .. "reads as a running joke about her cooking too much. In Part 5A it is the payoff, and "
        .. "in her note it is the proof she knew all along.",
  arms = { stage = 4, familiarity = 1 },
  beats = {
    { id = "dinner_list", kind = "sms",
      sms = { thread = "jackie", id = "side_dinner_open",
        messages = {
          { from = "jackie", text = "ma wants nine things from the market and i can read four of em" },
          { from = "jackie", text = "one of em might say 'goat'" },
          { from = "jackie", text = "help" },
        },
        replies = { { id = "yes", text = "On my way." },
                    { id = "tease", text = "You can't read your own mother's handwriting?" } },
        followups = { yes   = { { from = "jackie", text = "redwood. 20 min" } },
                      tease = { { from = "jackie", text = "it's CURSIVE, chica" }, { from = "jackie", text = "redwood. 20 min" } } } } },
    { id = "dinner_market", kind = "travel", place = "redwood", window = { 8.0, 18.0 },
      vo = { onArrive = "mama_ref" },
      journal = { quest = "side_dinner", phase = "main", objective = "shopping", text = "Get the nine things" } },
    { id = "dinner_table", kind = "scene", place = "coyote", window = { 19.0, 22.0 },
      intent = "Uses the shipped dinner system. One shot matters: the extra plate at the end of "
            .. "the table, laid, empty, and never mentioned by anybody.",
      vo = { open = "mama_ref", close = "thanks_v" },
      sets = { jackielives_side_dinner = 1 } },
  },
},

-- =============================================================================================
{ id = "side_card", title = "A Reading", slot = "before:p4", length = "10 min",
  logline = "Misty deals for Jackie. Jackie does not want to be dealt for.",
  intent = "Ten minutes, one card, and the mod's only supernatural gesture — kept ambiguous, "
        .. "because Misty's whole function in Cyberpunk is to be right in a way you can argue "
        .. "with. She deals him a card and reads it kindly. Which card she deals is DETERMINISTIC, "
        .. "picked from where the arc actually stands, so a player on a second playthrough gets a "
        .. "different one and feels the mod watching them.",
  plants = "Part 5. The card is on the bar in the epilogue, face up, matching the ending the "
        .. "player got. Nobody comments on it. If the player never played this quest there is no "
        .. "card, and that is fine — the epilogue does not depend on it.",
  arms = { stage = 4, familiarity = 2, arcAfter = 1 },
  cards = {
    { card = "The Tower",   when = "arc >= 2 and beacon == 0", read = "Something built is coming down. It is not a punishment; it is a structure that was wrong." },
    { card = "The Hanged Man", when = "arc >= 3 and ending == 0", read = "A man suspended, waiting, upside down, and choosing not to come down yet." },
    { card = "Death",       when = "episodes >= 3", read = "Not dying. Ending. Misty is very firm about the difference and says it twice." },
    { card = "The Star",    when = "familiarity >= 3", read = "Hope, but the thin kind you have to keep feeding." },
    { card = "The Fool",    fallback = true, read = "A man walking off a cliff with a dog barking at his heel. Misty says the dog is V." },
  },
  beats = {
    { id = "card_read", kind = "scene", place = "misty", window = { 10.0, 21.0 },
      actors = { "jackie", "misty" },
      vo = { open = "misty_ref", close = "deflect_light" },
      choices = {
        { id = "listen", text = "[Let her finish]", familiarity = 2 },
        { id = "scoff",  text = "It's cardboard, Misty.",
          outcome = "She agrees pleasantly and keeps reading. You cannot win an argument with "
                 .. "Misty and the mod should not let the player try." },
      },
      sets = { jackielives_side_card = "card" } },
  },
},

-- =============================================================================================
{ id = "side_houserules", title = "House Rules", slot = "anytime", length = "20 min",
  logline = "Two Valentinos, one card game, and a bar Jackie is supposed to be keeping calm.",
  intent = "The bar-fight comedy. It escalates in exactly three steps — an argument, a shove, a "
        .. "table — and the joke is that Jackie's fixer voice works perfectly right up until "
        .. "someone insults his mother's bar, at which point he is nineteen again. Fists only; "
        .. "nobody dies; Mama bans everyone for a week including Jackie.",
  plants = "Nothing. One quest in nine is allowed to plant nothing, and pretending otherwise is "
        .. "how a mod becomes homework.",
  arms = { stage = 4, familiarity = 0 },
  beats = {
    { id = "hr_fight", kind = "fight", place = "coyote", window = { 21.0, 27.0 },
      spawn = { note = "two Valentino civilians flipped hostile, melee only, no weapons drawn" },
      vo = { during = "combat_call", after = "deflect_light" },
      choices = {
        { id = "talk",  text = "[Talk them down]", outcome = "Works. Jackie is visibly disappointed.", familiarity = 1 },
        { id = "swing", text = "[Throw the first punch]", outcome = "Jackie is delighted and says so for two days.", familiarity = 2 },
      },
      sets = { jackielives_side_houserules = 1 } },
  },
},

-- =============================================================================================
{ id = "side_noodles", title = "The Noodle Question", slot = "anytime", length = "10 min",
  logline = "There are two noodle stands. Jackie has opinions. The other stand has opinions about Jackie.",
  intent = "The smallest quest in the mod and the one most likely to be someone's favourite. A "
        .. "ten-minute neighbourhood feud with no violence, no eddies and no consequence, in "
        .. "which V has to eat at both stands and pick one, and whichever they pick Jackie "
        .. "argues with. The mod remembers the answer and he brings it up for the rest of the "
        .. "game. That is the entire feature and it is worth building.",
  plants = "A running joke, which counts. In Part 5A he orders V's stand's food without being "
        .. "asked, and does not acknowledge that he has done it.",
  arms = { stage = 4, familiarity = 0 },
  beats = {
    { id = "noodle_taste", kind = "scene", place = "noodle", window = { 8.0, 14.0 },
      vo = { open = "lets_go", close = "deflect_light" },
      choices = {
        { id = "his",   text = "Yours. Obviously yours.",  outcome = "He does not believe V and interrogates them.", sets = { jackielives_side_noodles = 1 } },
        { id = "other", text = "The other one. Sorry.",     outcome = "Genuine betrayal. Ten minutes of it.",         sets = { jackielives_side_noodles = 2 }, familiarity = 1 },
        { id = "same",  text = "They're the same noodles, Jackie.", outcome = "The nuclear option. He does not speak on the walk back.", sets = { jackielives_side_noodles = 3 } },
      } },
  },
},

-- =============================================================================================
{ id = "side_shakedown", title = "Coyote's Cut", slot = "between:p2,p3", length = "25 min",
  logline = "Somebody has decided Mama Welles pays protection now.",
  intent = "The one side quest with real violence, deliberately placed in the gap between Parts 2 "
        .. "and 3 — after the player has learned that Jackie enjoys fighting, before they learn "
        .. "what it costs. It is a straight fight in a place the player cares about, and its real "
        .. "function is to let them see him be good at this ONE more time while he still is.",
  plants = "Part 4's third ending, again. Two quests argue for 'Ride it'. Neither of them says so.",
  arms = { stage = 4, arc = 2, familiarity = 1 },
  beats = {
    { id = "cut_sms", kind = "sms",
      sms = { thread = "jackie", id = "side_cut_open",
        messages = {
          { from = "jackie", text = "four guys came to my ma's bar today askin about insurance" },
          { from = "jackie", text = "they're comin back friday" },
          { from = "jackie", text = "i'm not askin you to come" },
          { from = "jackie", text = "i'm tellin you they're comin back friday" },
        },
        replies = { { id = "there", text = "Friday." }, { id = "cops", text = "Tell Padre. That's what he's for." } },
        followups = { there = { { from = "jackie", text = "yeah" } },
                      cops = { { from = "jackie", text = "padre's who sent em" },
                               { from = "jackie", text = "friday" } } } } },
    { id = "cut_fight", kind = "fight", place = "coyote", window = { 20.0, 24.0 },
      spawn = { note = "four gang-tier hostiles outside the bar; interior must stay safe — Mama is inside" },
      vo = { onSpawn = "angry_corp", during = "combat_joy", after = "thanks_v" },
      journal = { quest = "side_shakedown", phase = "main", objective = "hold_the_bar", text = "Keep them out of the bar" },
      sets = { jackielives_side_shakedown = 1 } },
  },
},

-- =============================================================================================
{ id = "side_lastcall", title = "Last Call", slot = "arc:p4_night_before", length = "20 min",
  logline = "The night before the operation. The bar is closed. He has the keys.",
  intent = "The pre-battle drink — a cliché, used on purpose, because the reason it is a cliché is "
        .. "that it works. It is the mod's last warm scene and it must not be clever. No plot "
        .. "advances. No new information. They sit in a closed bar and Jackie tells the "
        .. "single worst story he has, badly, for the fourth time, and V has the option of "
        .. "pretending they have not heard it.\n\n"
        .. "Every callback the save has earned fires here, one after another, and this is the "
        .. "beat where a player who played the side quests gets a visibly different scene from "
        .. "one who did not. That is the reward for all nine of them.",
  plants = "Nothing. It collects.",
  arms = { arc = 3, beat = "p3_ask" },
  beats = {
    { id = "lastcall", kind = "scene", place = "coyote", window = { 22.0, 28.0 },
      vo = { open = "lets_go", during = "misty_ref", close = "goodbye_soft" },
      callbacks = {
        "side_wall  -> 'I already got a wall, mano. Don't put me on it twice.'",
        "side_bike  -> he leaves the Arch keys on the bar and does not explain",
        "side_rico  -> Rico is wiping down tables and will not go home",
        "side_card  -> Misty's card is in his jacket pocket and he pretends it isn't",
        "side_noodles -> he has already ordered from V's stand",
        "side_dinner-> Mama comes down, looks at them both, and goes back up without a word",
      },
      choices = {
        { id = "heard",  text = "You've told me this one.", outcome = "'I know.' He tells it anyway." },
        { id = "listen", text = "[Let him tell it]", familiarity = 3 },
        { id = "truth",  text = "Are you scared?",
          outcome = "The only time anyone in the mod asks the question directly. He says 'nah' and "
                 .. "then sits there for eleven seconds without saying anything else, which is the "
                 .. "answer. The dialogue widget must hold the pause — do not close the node early.",
          sets = {} },
      },
      sets = { jackielives_side_lastcall = 1 } },
  },
},

}

-- =============================================================================================
-- OFFER PACING — how the mod suggests these without becoming a to-do list.
-- One offer at a time, at most one per in-game day, never during the arc's own beats, never
-- while Jackie is deteriorating on screen. If the player ignores an offer it is not repeated;
-- the quest stays available forever in his talk options instead. A mod that nags is a mod that
-- gets uninstalled at hour three.
-- =============================================================================================
M.offer = {
  maxPerDay      = 1,
  minHoursApart  = 20,
  neverDuringArc = true,
  order = { "side_noodles", "side_bike", "side_dinner", "side_houserules",
            "side_rico", "side_card", "side_wall", "side_shakedown", "side_lastcall" },
  note = "Order is by escalating intimacy, not by size — the mod should ask for a noodle opinion "
      .. "long before it asks anyone to stand at a memorial wall at 3am.",
}

return M
