--[[
  storyboard.lua — "Ghost in the Machine": the JackieLives 2.0 story, as DATA  (v2.0-a1)
  ============================================================================================
  This file is the SINGLE SOURCE OF TRUTH for the questline. It is not prose-with-code-nearby:
  the runtime (`arc.lua`) walks this table, the SMS generator (`tools/gen_messages.py`) reads the
  `sms` blocks out of it, the journal generator reads the `journal` blocks, and the design docs
  are GENERATED from it (`tools/gen_storyboard_doc.py`). If the story changes, it changes here,
  once, and everything downstream follows. Nothing else is allowed to hold story state.

  WHY DATA AND NOT CODE. The mod already learned this lesson twice (dialogue trees, the venue
  schedule): content that lives in `if` statements can only be edited by someone who can read
  Lua, and it drifts from the document that describes it. Content that lives in a table can be
  read by a writer, diffed in a pull request, validated by a test harness offline
  (`tools/test_storyboard.lua`), and rendered into a storyboard document that is true by
  construction.

  --------------------------------------------------------------------------------------------
  READING THIS FILE (for Antonia — no Lua needed)
  --------------------------------------------------------------------------------------------
  Everything is a labelled list. `{ }` is a group, `key = value` is a labelled fact.
  A BEAT is one dramatic unit — one thing that happens. It says:

      id          a permanent name. NEVER rename one: saves store it.
      title       what a player would call it.
      kind        what sort of thing it is (see KINDS below).
      intent      the writer's note: what this beat is FOR, dramatically. Read these first —
                  they are the storyboard.
      arms        the conditions that must all be true before it can happen.
      place       where (a key from M.PLACES).
      window      when, in in-game hours, e.g. { 20.0, 26.0 } = 20:00 until 02:00.
      actors      who is present.
      vo          which Jackie recording plays (by CASTING SLOT, not by raw id — see §CASTING).
      sms         a text message this beat sends (the words are right here, verbatim).
      shard       a readable shard this beat makes available (the words are right here).
      journal     the tracked quest objective this beat starts/finishes.
      choices     what V can say/do, and what each choice costs or sets.
      sets        the facts this beat writes when it completes.
      next        the beat that becomes armable afterwards.

  KINDS
      "episode"   a scripted physical event on Jackie's body (a stumble, a blackout).
      "travel"    go somewhere with him; the objective is arrival.
      "talk"      a dialogue node with choices, using the shipped dialogue widget.
      "fight"     spawn hostiles; Jackie fights beside V (the `blaze.lua` pattern).
      "sms"       a text lands. No presence required — this is the beat that can happen while
                  the player is doing something else entirely, which is exactly the point.
      "shard"     a readable document becomes available.
      "choice"    a fork with durable consequences.
      "scene"     a staged moment with no combat and no fork — a memory the player watches.
      "gig"       an existing-systems job: summon him, go, shoot, get paid.

  --------------------------------------------------------------------------------------------
  THE STORY, IN ONE PARAGRAPH
  --------------------------------------------------------------------------------------------
  Vik had a dying man on the table and no time, so he built Jackie back out of what was in the
  room — salvaged Arasaka military chrome pulled from the same heist that killed him. It worked.
  It also left two Arasaka things inside him: a beacon that is telling somebody where he is, and
  an unfinished suppression daemon that is slowly learning to use his hands. The beacon is the
  outside threat, the daemon is the inside one, and the fix for the first wakes the second. The
  questline ends with an operation Jackie refuses to decide about, because the one thing he can't
  do is choose what kind of man he is now — so he asks V to do it for him.

  THE DRAMATIC QUESTION
      What did it cost to keep Jackie Welles alive — and who gets to decide whether he pays it?

  THEME — SALVAGE
      Everyone here is built out of parts meant for something else. Vik built Jackie from what
      was on the table. Jackie built a quiet life out of what was left of a merc. V is building
      a friendship out of guilt. The ending asks whether a salvaged thing is still the thing.

  THE TWO CHARACTER ARCS (this is what the beats are actually tracking)
      JACKIE  wants to stay out, and to be enough for Mama, Misty and V without a gun in his
              hand. He needs to admit that the man who died at Konpeki is not coming back and
              choose what he is instead. His flaw is the lie "I'm fine, mano" — and his arc
              completes the first time he tells V the truth BEFORE being asked.
      V       wants to keep Jackie safe. V needs to stop managing him. V's flaw is already
              canon in this mod: at the reunion, V LIES to him about the Relic "for his own
              good". Part 3 detonates that lie; Part 4 is where V either takes the decision
              Jackie offers (managing him one last time) or hands it back (letting him be a
              person). Neither is punished. That is the whole point.

  SETUPS AND PAYOFFS (plant early, detonate late — nothing in this mod is decoration)
      PLANTED                                   PAID OFF
      V's reunion lie about the Relic (shipped) Part 3 "The Timestamps" — he catches V lying
      Misty's tarot card (side: A Reading)      Part 5 — the card names the ending V got
      Jackie's bike keys (side: The Arch)       Part 5C — the getaway; Part 5A — he sells it
      Rico, the kid Jackie won't break (side)   Part 3 takeover victim; Part 5C he brings help
      Mama's empty plate (side: Mama's Errand)  Part 5A — the plate is finally used
      Jackie's own name on the memorial wall    Part 4 — "I already got a wall. Don't put me on
        (side: Last Rites)                        it twice."
      He ENJOYS the first firefight (Part 2)    Part 4 ending C is a choice, not a mistake
      Nix's spoof "degrades" (Part 2 choice)    Part 5 — one last squad arrives regardless

  --------------------------------------------------------------------------------------------
  PACING — the rule that keeps this from feeling like a checklist
  --------------------------------------------------------------------------------------------
  Parts arm on LIVED TIME, not on a marker. Each part needs N in-game days since the previous one
  AND a familiarity tier. Jackie's deterioration should read as something happening to a friend
  you already live with. A player who never talks to him never gets Part 3 — and that is correct:
  he would not tell them.

  Familiarity tiers (`familiarity.lua`): 0 Choom · 1 Close · 2 Trusted · 3 Family.

  --------------------------------------------------------------------------------------------
  SAFETY RULES CARRIED OVER FROM THE RETRIEVAL QUEST (learned the hard way — see TODO v1.56/v1.64)
  --------------------------------------------------------------------------------------------
   1. Every arming condition is checked against a fact we have POSITIVELY CONFIRMED.
      Unknown = stay silent. Never guess, never spoil.
   2. Nothing here may fire before `jackielives_stage == 4` (REUNITED). The whole arc is
      downstream of the shipped questline; there is no path into it from a pre-heist save.
   3. Every part ships with a manual start button in the mod menu, so a failed auto-arm degrades
      to "the player presses a button", never to "the mod is dead".
   4. Every part ends at a STABLE RESTING STATE. A player who stops after Part 2 is not left
      mid-sentence, and Jackie does not deteriorate in the background of a game they have
      stopped playing.
   5. The upsetting beats (the takeover, and the raid) are behind their own settings toggles,
      default ON but announced on the card that opens the arc. A player who has spent forty
      hours with this man as a friend gets to decide whether they watch him turn.

  --------------------------------------------------------------------------------------------
  §CASTING — how the words work
  --------------------------------------------------------------------------------------------
  Jackie can only ever say the ~1200 lines he actually recorded. So a beat NEVER names a String
  ID directly; it names a CASTING SLOT (a dramatic function, e.g. "deflect_light"), and
  `M.CASTING` maps that slot to a list of real recordings. This decoupling is load-bearing:
   * the writing can be finished before the casting is,
   * a slot with no recording is a LOUD failure in `tools/test_storyboard.lua` rather than a
     silent one in-game,
   * and one recasting fixes every beat that uses the slot.
  Candidate ids are gathered in `docs/research/arc_casting.md`. IDs ARE STRINGS. Never
  `tonumber()` one — they are ~2e18 and a Lua double corrupts them silently.

  Everyone who is NOT Jackie communicates by SMS, shard, or journal entry. This is not a
  compromise forced by the ceiling; it is how people actually communicate about a thing they are
  hiding. A subtitle with no voice behind it reads as a broken mod. A text message reads as a
  text message.
--]]

local M = {}

M.VERSION = "2.0-a1"

-- ===========================================================================================
-- PLACES — every location the arc uses.
-- `configKey` = already captured and live in Config.locations (see docs/research/quest_atlas.md).
-- `needsCapture = true` = Antonia has to stand there in-game and press the capture key. Those are
-- listed in one place at the bottom of this file (M.CAPTURE_LIST) so the ask is a short errand,
-- not a scavenger hunt. Until captured, the engine substitutes `fallbackKey` and logs it.
-- ===========================================================================================
M.PLACES = {
  coyote      = { configKey = "coyote",    label = "El Coyote Cojo",           note = "Mama's bar. Home ground. 6 waypoints captured incl. upstairs table + railing." },
  coyote_back = { needsCapture = true, fallbackKey = "coyote", label = "El Coyote — back room",
                  capture = "Stand in the back/storeroom area behind the bar, facing the door.",
                  note = "The takeover happens here: controlled, private, and thirty feet from Mama." },
  misty       = { configKey = "misty",     label = "Misty's Esoterica",         note = "Shop floor. Misty present." },
  vik         = { configKey = nil, retrievalKey = "vikPos", label = "Vik's clinic",
                  note = "retrieval.lua M.Config.vikPos — captured, the ripperdoc chair." },
  redwood     = { configKey = "redwood",   label = "Redwood Market",            note = "Captured, not on his daily schedule — so a quest can put him there without fighting the venue system." },
  noodle      = { configKey = "noodle",    label = "The noodle bar",            note = "Jackie's stall. Where nothing bad ever happens — which is why the arc uses it for relief beats only." },
  afterlife   = { configKey = "afterlife", label = "The Afterlife",             note = "Nix. 4 waypoints captured." },
  lizzie      = { configKey = "lizzie",    label = "Lizzie's Bar",              note = "Opens 21:00." },
  hideout     = { configKey = nil, retrievalKey = "hideoutPos", label = "Rocky Ridge garage",
                  note = "Where V found him in Act I. The arc ENDS here in branch C — the rhyme is deliberate." },
  revflash    = { configKey = nil, cfgPath = "revflash.pos", label = "Rocky Ridge — BD shack", note = "Captured. Used as the relay-mast stand-in until a mast is captured." },
  mast        = { needsCapture = true, fallbackKey = "revflash", label = "Badlands comms mast",
                  capture = "Any radio/comms mast out past Rocky Ridge with a driveable approach. Stand at its base.",
                  note = "Part 2's jammer plant. The fallback works fine for testing." },
  wall        = { needsCapture = true, fallbackKey = "coyote", label = "The Heywood memorial wall",
                  capture = "A wall of memorial graffiti/candles in Heywood (there are several near Vista del Rey). Face the wall.",
                  note = "Side quest 'Last Rites'. Jackie's own name is on it." },
  gig_lot     = { needsCapture = true, fallbackKey = "hideout", label = "The Part 3 gig site",
                  capture = "Any open industrial lot with cover, ideally Santo Domingo.",
                  note = "One firefight. Needs room and no civilians." },
}

-- ===========================================================================================
-- CASTING SLOTS — dramatic function -> real recordings.
-- Filled from docs/research/arc_casting.md. `ids` is a candidate list; the engine picks one at
-- random per firing (with a no-immediate-repeat rule) so a beat replayed on a second save does
-- not sound identical. A slot with an EMPTY list is a hard test failure, not a shrug.
-- `text` is the subtitle we show, which must be what the recording actually SAYS — never a
-- caption of what we wish it said (see CLAUDE.md, casting rules).
-- ===========================================================================================
-- WHAT THE LIBRARY ACTUALLY HAS (audited 2026-08-25, docs/research/arc_casting.md — all 1101
-- lines). Three findings changed the story, and they are recorded here rather than in a design
-- doc because this is the file that has to obey them:
--
--   1. THERE IS NO "I'M AFRAID" TAKE. Zero hits for afraid/scared/terrified/frightened in the
--      whole corpus. The original design promised Jackie says it "in his own voice, because the
--      library has that take" — it does not. This turned out to IMPROVE the arc: a man whose
--      whole flaw is that he can't say things out loud does not get to say the biggest one out
--      loud. The fear admission is now a 4am text, and the voiced beat beside it is
--      "Worried 'bout me. Been for a while." — him naming it at one remove, which is all he has.
--   2. THERE IS NO WEIGHTY FAREWELL. Every goodbye take is a casual "Ahí luego, V" built for a
--      companion you'll see again in five minutes, and six of the eight are already spent by
--      retrieval.lua. So no epilogue hangs on a closing line. They are carried by staging —
--      a plate, a routine, a firefight — with an ordinary "see ya" underneath. The
--      `goodbye_final` slot has been DELETED rather than faked.
--   3. NOTHING NAMES THE THREAT. No line mentions a beacon, a daemon, a netrunner, Nix, or a
--      snatch squad. Every act of naming in this arc happens in text, which is what the design
--      already assumed — now confirmed rather than hoped.
--
-- Ids below are the audited picks. `spent = true` means retrieval.lua already uses it — avoid
-- stacking it in the same scene, and never make it the only line in a beat.
M.CASTING = {
  -- Slot            real recordings                              what it carries, dramatically
  deflect_light   = { ids = { "1725480866495123456" },
                      need = "The brush-off. 'Don't worry, got this.' The closest the corpus comes to 'I'm fine' — there is no better one." },
  deflect_hard    = { ids = { "1678035821641031680", "1741832357434814464" },
                      need = "The same deflection with the shutters down. 'Agh, I dunno…' / 'Agh, don't thrill you, that?'" },
  pain_short      = { ids = { "1638689384933675008", "1226494768812494848" },
                      need = "Non-verbal distress. 1638… is pure grunt with no plot hook — the workhorse of every episode." },
  pain_bad        = { ids = { "2014500975731875864", "1208276870125637632", "1926923970895048704" },
                      need = "Real damage. 'Argh… I'm leakin' a little…' Used for the midpoint collapse and the takeover recovery." },
  confused        = { ids = { "1678035821641031680" },
                      need = "Disoriented. Doubles with deflect_hard on purpose — being lost and covering it are the same sound in him." },
  worried_remove  = { ids = { "2028635009449914368", "1795303424698900480" },
                      need = "THE arc's emotional line, and it is at one remove: 'Worried 'bout me. Been for a while.' He can name that someone ELSE is frightened for him. That is his whole range, and the arc is built around the gap." },
  angry_corp      = { ids = { "1671130383003639808", "1785258183320547328", "1904018262013562880" },
                      need = "Corp hate. 'I hate these 'borg fuckers.' Also carries the recognition beat — he can't say 'they came for me', so he says what he thinks of them." },
  watched         = { ids = { "2238744397675143176" },
                      need = "'Watch it, V. They got cams.' Uncannily on-theme for the surveillance thread. One of the luckiest finds in the audit." },
  combat_call     = { ids = { "1653073643632050176", "2238685622691864584", "2238165104918175752",
                              "2238682834201124868", "1861972099194613760" },
                      need = "Tactical barks. Deep pool, no scarcity — the fights are the one place the library is generous." },
  combat_joy      = { ids = { "2257914255984926728", "1616176656287490048", "2238069786960633864" },
                      need = "He is ENJOYING this. Part 4's third ending is argued for entirely by these three lines." },
  urgent_go       = { ids = { "2259031306614972424" },
                      need = "'There's time for thinkin', time for gettin' the fuck out! Let's go!' Unspent, high-urgency — saved for the snatch squad." },
  thanks_v        = { ids = { "1866254590956171264", "1993514843414274048" },
                      need = "The corpus has exactly TWO real V-directed gratitude lines. Budget them: 1866… anchors Part 4's aftermath, 1993… closes Part 3. Do not spend either early." },
  lets_go         = { ids = { "872106507270864912", "1687435597683843072", "1688508282677452800" },
                      need = "Movement. Unspent alternatives to the ones retrieval.lua already drains." },
  money_talk      = { ids = { "1802689463280660480", "1722898438958141456" },
                      need = "'Won't come cheap. And it'll have to be done on the sly — no trail, hard eddies only.' It reads as though it were recorded for this arc." },
  mama_ref        = { ids = { "1625680459640795136", "1917219479049138176" },
                      need = "Only two exist in 1101 lines, both about her cooking — which is why Part 5A is a dinner and not a conversation." },
  misty_ref       = { ids = { "1794044297741217792", "2008326252916568064", "1790882350032015360" },
                      need = "'Misty asked me… not to take this job.' Already voiced, already exactly Part 3's objection." },
  vik_ref         = { ids = { "1705592372028665856", "1861942814782189568", "1661848757298057216" },
                      need = "'First stop – ripperdoc?' Three lines total in the corpus. Part 1's objective gets the good one." },
  chrome_ref      = { ids = { "1711253382494904320" },
                      need = "'Great piece of chrome. Feels like fucking Christmas morning.' Tonally WRONG for the reveal — which is why it belongs early, before he knows. Irony is free." },
  goodbye_soft    = { ids = { "1866291879677685760" },
                      need = "The one unspent 'Ahí luego. I will.' Everything else in the farewell pool is burned by retrieval.lua." },
  laugh           = { ids = {}, need = "A real laugh. UNCAST — audit found none clean; relief beats fall back to lets_go/toast." },
  toast           = { ids = {}, need = "A toast. UNCAST — 'Last Call' is carried by staging and V's side of the dialogue." },
}

-- ===========================================================================================
-- FACTS — everything the arc persists. Names are permanent; a save holds them.
-- ===========================================================================================
M.FACTS = {
  arc         = "jackielives_arc",        -- 0 not started .. 5 epilogue done. The spine.
  beat        = "jackielives_arc_beat",   -- index into the current part's beat list
  trace       = "jackielives_trace",      -- Part 2 heat, 0..100
  beacon      = "jackielives_beacon",     -- 0 live, 1 burned, 2 spoofed
  ending      = "jackielives_arc_end",    -- 0 none, 1 Clean, 2 Caged, 3 Ride it
  chose_by    = "jackielives_arc_chosen_by", -- 1 = V chose, 2 = V handed it back to Jackie
  pull_now    = "jackielives_arc_pullnow",-- Part 1 framing choice: he wanted out early
  caught_lie  = "jackielives_arc_caughtlie", -- Part 3: he caught V lying about the Relic
  episodes    = "jackielives_arc_episodes",  -- how many episodes the player has WITNESSED
  money       = "jackielives_arc_funded", -- Part 3 gig done
  knows_misty = "jackielives_arc_misty",  -- Misty worked it out
  knows_mama  = "jackielives_arc_mama",   -- Mama worked it out (she always does)
  rico        = "jackielives_side_rico",  -- the kid lives / owes them
  bike        = "jackielives_side_bike",  -- keys returned
  card        = "jackielives_side_card",  -- Misty dealt his card; which one is stored here
  jammer      = "jackielives_arc_jammer", -- Nix's jammer is paid for and in V's hands
}

-- ===========================================================================================
-- THE ARC
-- ===========================================================================================
M.arc = {
  id    = "ghost",
  title = "Ghost in the Machine",
  fact  = M.FACTS.arc,
  -- The card the player sees when the arc opens. It is also the content warning, because
  -- rule 5 above says the player decides whether they watch him turn.
  opening_card = {
    title = "Jackie Lives — Ghost in the Machine",
    text  = "Something's wrong with Jackie, and it's been wrong for a while.\n\n"
         .. "This is a story that plays out over in-game weeks, on its own schedule. It'll find you.\n\n"
         .. "It gets dark in places. If you'd rather it didn't, the settings menu has switches for the "
         .. "two hardest scenes — turn them off and the story still works.",
    duration = 14.0,
  },

  parts = {

  -- =========================================================================================
  -- PART 1 — "STATIC"          the reveal.        ACT I turn.
  -- =========================================================================================
  {
    id = "p1", title = "Static", arcValue = 1,
    logline = "Jackie's hand stops working for four seconds, and he lies about it. That night he "
           .. "tells the truth in a text, because he can't say it out loud.",
    intent = "Establish the flaw (he lies), the symptom (his body), and the private channel (SMS) "
          .. "in that order. The player should finish this part understanding that Jackie will "
          .. "always tell them less in person than in writing — which is the mechanic the whole "
          .. "arc is built on.",
    arms = { stage = 4, daysSinceStage = 3, familiarity = 1 },

    beats = {

      { id = "p1_episode", title = "The first one you see", kind = "episode",
        intent = "Not a cutscene. It happens mid-follow, while the player is going somewhere else, "
              .. "and it is over before they have finished reacting. Four seconds. The player "
              .. "should not be sure what they just saw.",
        arms = { following = true, outdoors = true, notInCombat = true },
        place = "any", window = { 6.0, 24.0 },
        actors = { "jackie" },
        script = {
          "halt him (existing halt/workspot machinery)",
          "hold a gesture pose — his right hand",
          "cut a VO line short mid-word, 0.4s of silence, re-fire it (the audio glitch)",
          "short screen distortion (the existing glitch effect used at reunion)",
          "release; he walks on",
        },
        vo = { after = "deflect_light" },
        sets = { [M.FACTS.episodes] = "+1" },
        next = "p1_sms_night",
        notes = "If the player asks him about it (talk prompt within 30s), he uses deflect_light "
             .. "again, not a new line. He has nothing else to say yet.",
      },

      { id = "p1_sms_night", title = "The text", kind = "sms",
        intent = "THE beat that justifies building the SMS system. It is private, it is deniable, "
              .. "and it is how a man hides a symptom while telling someone about it. The last "
              .. "line is the ask that makes V complicit.",
        arms = { afterBeat = "p1_episode", delayHours = 5, window = { 23.0, 27.0 } },
        sms = {
          thread = "jackie",
          id = "arc_p1_night",
          messages = {
            { from = "jackie", text = "you awake" },
            { from = "jackie", text = "that thing earlier. my hand." },
            { from = "jackie", text = "it wasn't the first time" },
            { from = "jackie", text = "third time this month" },
            { from = "jackie", text = "don't tell Misty" },
          },
          replies = {
            { id = "worried",  text = "How long, Jackie?",            sets = {} },
            { id = "vik",      text = "We're going to Vik. Tomorrow.", sets = {} },
            { id = "respect",  text = "Okay. I won't.",                sets = {} },
          },
          followups = {
            worried = { { from = "jackie", text = "since the badlands. maybe before." },
                        { from = "jackie", text = "go to sleep, chica. it's late." } },
            vik     = { { from = "jackie", text = "figured you'd say that" },
                        { from = "jackie", text = "fine. tomorrow." } },
            respect = { { from = "jackie", text = "thanks" },
                        { from = "jackie", text = "…we're still going to vik though right" },
                        { from = "jackie", text = "yeah. figured." } },
          },
        },
        sets = { [M.FACTS.arc] = 1 },
        next = "p1_to_vik",
      },

      { id = "p1_to_vik", title = "Take Jackie to Vik", kind = "travel",
        intent = "The first REAL tracked objective this mod has ever shipped. It is deliberately "
              .. "a small one: the whole point of Part 1 is to prove the journal chain on "
              .. "something that cannot fail interestingly.",
        arms = { afterBeat = "p1_sms_night" },
        place = "vik", window = { 8.0, 22.0 },
        actors = { "jackie", "vik" },
        journal = { quest = "ghost", phase = "p1", objective = "take_jackie_to_vik",
                    text = "Take Jackie to Vik" },
        summon = { required = true, note = "He'll come. He already agreed in the text — and if the "
                .. "player never texted back, he agrees in person, grudgingly." },
        vo = { onArrive = "vik_ref" },
        next = "p1_scan",
      },

      { id = "p1_scan", title = "Ripperdoc scan — patient: J. Welles", kind = "shard",
        intent = "The reveal lands as a DOCUMENT, not a speech, for three reasons: Vik has no new "
              .. "VO, a scan is what a ripperdoc would actually produce, and a document stays in "
              .. "the Codex where the player can re-read it when Part 3 makes it matter.",
        arms = { afterBeat = "p1_to_vik", atPlace = "vik" },
        place = "vik",
        shard = {
          id = "arc_scan",
          title = "Ripperdoc scan — patient: J. Welles",
          author = "Viktor Vektor",
          body = {
            "PATIENT: Welles, J. — post-trauma review, 14 months.",
            "",
            "Two foreign objects. Neither of them mine.",
            "",
            "OBJECT ONE. Militech-pattern housing, Arasaka firmware. Sits in the left shoulder "
              .. "assembly. It's a factory anti-theft telemetry unit — mil-spec parts phone home so "
              .. "the company knows where its property is. It has been transmitting, on a low duty "
              .. "cycle, since the night I put it in him. For most of that time nobody was listening.",
            "",
            "OBJECT TWO. Not hardware. There's a suppression daemon resident in his operating "
              .. "system — corp security payload, the kind a netrunner burns into you to shut your "
              .. "limbs off. It never finished executing. He flatlined halfway through the attack, "
              .. "and a dead man is a bad host, so it stalled. It has not stalled since. It has been "
              .. "learning his neural pattern for fourteen months.",
            "",
            "For the record, because he won't ask and she will:",
            "",
            "I had a dying man on my table and four hours. What I put in him is what was in the room. "
              .. "It came off the same job that killed him. I'd do it again — he's breathing — but "
              .. "nobody should pretend I did surgery that night. I did salvage.",
            "",
            "— V.V.",
          },
        },
        sets = { [M.FACTS.arc] = 1 },
        next = "p1_choice",
      },

      { id = "p1_choice", title = "Pull it now, or find the proper fix", kind = "choice",
        intent = "A first-act turn that does NOT branch the plot — it branches the CHARACTER. "
              .. "Whichever way the player goes, Vik refuses to operate blind, so the story is the "
              .. "same story. What changes is whether Jackie spends the next four parts knowing he "
              .. "asked to get out early and was overruled. That colours every line he has.",
        arms = { afterBeat = "p1_scan" },
        place = "vik", actors = { "jackie", "vik" },
        choices = {
          { id = "pull_now", text = "Take it out. All of it. Now.",
            outcome = "Vik: he'd survive it. He'd also be a man who gets winded on stairs. "
                   .. "Jackie says yes anyway. Vik refuses to cut blind — he doesn't know what the "
                   .. "daemon does if you unplug its host.",
            sets = { [M.FACTS.pull_now] = 1 },
            note = "Sets the sadder colour. Jackie's later lines lean on deflect_hard and afraid." },
          { id = "proper_fix", text = "We do it right. Whatever it takes.",
            outcome = "Jackie is relieved and hides it badly. He has been dreading being told to "
                   .. "give up the chrome, which tells the player something he hasn't said.",
            sets = { [M.FACTS.pull_now] = 0 } },
          { id = "ask_jackie", text = "It's your body, Jackie.",
            outcome = "He doesn't answer. That is the answer, and it is the seed of Part 4 — the "
                   .. "man cannot make this decision about himself.",
            sets = { [M.FACTS.pull_now] = 0, [M.FACTS.chose_by] = 0 },
            note = "The best line in the beat. Plant it here so Part 4's ending doesn't come from "
                .. "nowhere." },
        },
        vo = { close = "thanks_v" },
        sets = { [M.FACTS.arc] = 1 },
        next = nil,
      },
    },

    rest = "V and Jackie both know. Nobody else does. Nothing is chasing anybody yet.",
  },

  -- =========================================================================================
  -- PART 2 — "PHONE HOME"      the beacon.        ACT IIa: fun and games, then the midpoint.
  -- =========================================================================================
  {
    id = "p2", title = "Phone Home", arcValue = 2,
    logline = "The beacon in Jackie's shoulder has been talking to Arasaka for fourteen months, "
           .. "and somebody has finally started listening.",
    intent = "Turn the premise into a MECHANIC. Heat accrues while Jackie is out in the world with "
          .. "V, which means the threat is generated by the thing the player most enjoys — having "
          .. "him around. The quiet horror of this part is not the snatch squads. It is that "
          .. "Jackie is happier in the first firefight than he has been since he came home, and "
          .. "the player notices before he does.",
    arms = { arc = 1, daysSincePart = 4, familiarity = 1 },

    heat = {
      fact = M.FACTS.trace,
      accrual = {
        note = "per in-game hour, only while Jackie is spawned and with V",
        watson = 4.0, citycentre = 5.0, heywood = 2.5, santodomingo = 2.0, pacifica = 1.5,
        badlands = 0.5, indoors_home = 0.0,
      },
      thresholds = {
        { at = 25,  event = "p2_unknown_number" },
        { at = 55,  event = "p2_drone" },
        { at = 85,  event = "p2_squad" },
      },
      note = "Heat does NOT decay on its own. It is a problem that follows them home, and that is "
          .. "the difference between a marker on a map and a story. It only stops in p2_choice.",
    },

    beats = {

      { id = "p2_unknown_number", title = "Unknown number", kind = "sms",
        intent = "The cheapest dread in the whole mod. Two lines, no sender, no follow-up, and "
              .. "then nothing happens for days. The player will check the phone again.",
        arms = { heat = 25 },
        sms = {
          thread = "unknown", contactLabel = "Unknown",
          id = "arc_p2_unknown",
          messages = {
            { from = "unknown", text = "Asset 7741-B." },
            { from = "unknown", text = "Property of Arasaka Corporation. Recovery is in progress." },
          },
          replies = {
            { id = "who", text = "Who is this?" },
            { id = "nothing", text = "[Say nothing]" },
          },
          followups = {
            who = { { from = "unknown", text = "[The number no longer exists.]" } },
            nothing = {},
          },
        },
        next = "p2_drone",
      },

      { id = "p2_drone", title = "Something's watching", kind = "scene",
        intent = "Escalation without violence. A surveillance drone holds station over wherever "
              .. "Jackie is idling. The player can shoot it or leave it; both are the same "
              .. "outcome, because it already saw him. Giving the player a meaningless choice "
              .. "here is deliberate — it teaches them that they cannot shoot their way out of "
              .. "this particular problem, one part before they try.",
        arms = { heat = 55, afterBeat = "p2_unknown_number" },
        place = "jackie_current", window = { 6.0, 26.0 },
        script = { "spawn surveillance drone at 30m altitude over Jackie's venue",
                   "it holds for ~40s, then leaves regardless",
                   "if destroyed: Jackie reacts (angry_corp), heat +10 anyway" },
        vo = { onNotice = "angry_corp" },
        next = "p2_squad",
      },

      { id = "p2_squad", title = "They came for him", kind = "fight",
        intent = "The first real fight of the arc, and the one the player will remember for the "
              .. "wrong reason. Jackie is GOOD at this and he is glad. Cast combat_joy here, not "
              .. "combat_call — the whole of Part 4's third ending is being set up in this "
              .. "firefight.",
        arms = { heat = 85, afterBeat = "p2_drone", notInMainQuest = true, outdoors = true },
        place = "near_jackie", window = { 6.0, 26.0 },
        actors = { "jackie", "arasaka_squad" },
        spawn = {
          { record = "Character.q005_arasaka_kill_squad_4_officer", count = 1, note = "VERIFIED record (AMM db)" },
          { record = "Character.q005_arasaka_kill_squad_4",         count = 2, note = "used by blaze.lua; unverified outside game" },
          { record = "Character.q005_arasaka_kill_squad_1",         count = 2, note = "ditto" },
        },
        vo = { onSpawn = "watched", during = "combat_joy", after = "angry_corp" },
        journal = { quest = "ghost", phase = "p2", objective = "survive_squad",
                    text = "Survive the Arasaka snatch team" },
        next = "p2_confirm",
        notes = "Uses blaze.lua's spawn-hostiles-and-let-Jackie-fight pattern. Never fires during a "
             .. "main quest, indoors, or in a no-combat zone — the same gates the summon uses.",
      },

      { id = "p2_confirm", title = "That was a snatch team", kind = "talk",
        intent = "Jackie names it, because he is the one in the room who has seen a corp recovery "
              .. "crew before. Give the exposition to the character it makes look competent.",
        arms = { afterBeat = "p2_squad", delayMinutes = 2 },
        place = "any", actors = { "jackie" },
        vo = { open = "angry_corp", close = "watched" },
        choices = {
          { id = "how", text = "How'd they find you?",
            outcome = "He doesn't know. V does — the scan said so. This is where V has to decide "
                   .. "whether to say 'you're broadcasting' out loud." },
          { id = "beacon", text = "You've been transmitting. Since Vik put you back together.",
            outcome = "He takes it badly and quietly. 'So I brought 'em here. To Mama's street.'",
            sets = {} },
        },
        next = "p2_nix",
      },

      { id = "p2_nix", title = "Someone who can read a handshake", kind = "travel",
        intent = "Nix is the right call for structural reasons, not just flavour: he is "
              .. "accessible, entangled in no romance or quest, and canonically the man you take "
              .. "weird chrome to. He communicates in text — no VO, no problem.",
        arms = { afterBeat = "p2_confirm" },
        place = "afterlife", window = { 18.0, 27.0 },
        actors = { "nix" },
        journal = { quest = "ghost", phase = "p2", objective = "find_netrunner",
                    text = "Find someone who can read corp telemetry — try the Afterlife" },
        sms = {
          thread = "nix", contactLabel = "Nix",
          id = "arc_p2_nix",
          messages = {
            { from = "nix", text = "Heard you were asking." },
            { from = "nix", text = "A mil-spec tracker doesn't talk to Arasaka Tower. It talks to whatever mast it can see, and the mast talks to the tower. That's the seam." },
            { from = "nix", text = "I can build you something that sits in that seam. Two grand, and I don't want to know whose shoulder it's in." },
          },
          replies = {
            { id = "pay",  text = "Done. [€$2000]",  cost = 2000, sets = { jackielives_arc_jammer = 1 } },
            { id = "haggle", text = "Two grand's steep for a box.", },
          },
          followups = {
            pay = { { from = "nix", text = "Pickup's at the Afterlife. Don't bring him with you." } },
            haggle = { { from = "nix", text = "It's steep for a box. It's cheap for a man." },
                       { from = "nix", text = "Two grand." } },
          },
        },
        next = "p2_mast",
      },

      { id = "p2_mast", title = "The relay", kind = "travel",
        intent = "A drive out of the city with him, which the mod's vehicle systems already do "
              .. "well, and which buys the arc its one quiet scene before the midpoint. Cast the "
              .. "ride with light lines. Let the player enjoy him.",
        arms = { afterBeat = "p2_nix", fact = { "jackielives_arc_jammer", 1 } },
        place = "mast", window = { 0.0, 24.0 },
        actors = { "jackie" },
        journal = { quest = "ghost", phase = "p2", objective = "plant_jammer",
                    text = "Plant Nix's jammer at the relay mast" },
        vo = { onDrive = "chrome_ref", onArrive = "lets_go" },
        optional_ambush = { chance = 0.5, note = "reuse p2_squad's spawn list, half strength" },
        next = "p2_choice",
      },

      { id = "p2_choice", title = "Burn it or spoof it", kind = "choice",
        intent = "A real strategic fork with a long fuse. Neither option is safe; they are unsafe "
              .. "at different times, which is the only kind of choice worth writing.",
        arms = { afterBeat = "p2_mast", atPlace = "mast" },
        actors = { "jackie", "nix_remote" },
        choices = {
          { id = "burn", text = "Burn it. Kill the beacon.",
            outcome = "The beacon dies. Heat stops accruing and resets to zero — Jackie can walk "
                   .. "through Night City again. But a mil-spec unit going dark is itself an event, "
                   .. "and Arasaka logs it. This is what makes Part 5's raid possible.",
            sets = { [M.FACTS.beacon] = 1, [M.FACTS.trace] = 0 } },
          { id = "spoof", text = "Spoof it. Let them keep listening to a lie.",
            outcome = "Nix feeds it a loop: asset in transit, catalogued, unremarkable. Heat "
                   .. "freezes where it is and never resets. The spoof degrades. One late squad "
                   .. "arrives no matter what the player does.",
            sets = { [M.FACTS.beacon] = 2 } },
        },
        next = "p2_midpoint",
      },

      { id = "p2_midpoint", title = "The pulse", kind = "episode",
        intent = "THE MIDPOINT REVERSAL, and the single most important structural beat in the arc. "
              .. "The player has just solved the problem the whole part was about. Ninety seconds "
              .. "later, the jammer pulse — or the beacon dying, depending on the branch — reaches "
              .. "the other Arasaka thing inside him and wakes it up properly. The victory caused "
              .. "the disaster. Everything after this is downhill and it is the player's own doing.",
        arms = { afterBeat = "p2_choice", delayMinutes = 2 },
        place = "mast",
        script = {
          "Jackie drops mid-sentence — a full collapse, not a stumble",
          "eight seconds of nothing; V cannot wake him",
          "he comes back up on his own, doesn't know he went down",
          "audio glitch on the recovery line — the SAME glitch as p1_episode, longer",
        },
        vo = { onWake = "confused", after = "deflect_hard" },
        sets = { [M.FACTS.arc] = 2, [M.FACTS.episodes] = "+1" },
        next = nil,
      },
    },

    rest = "Jackie can walk through Night City again. The other problem just woke up.",
  },

  -- =========================================================================================
  -- PART 3 — "PASSENGER"       the daemon.        ACT IIb: dread, then all is lost.
  -- =========================================================================================
  {
    id = "p3", title = "Passenger", arcValue = 3,
    logline = "The thing in Jackie's operating system has spent fourteen months learning how to be "
           .. "him, and it is getting good at it.",
    intent = "This is the horror part, and horror in this mod means MEDICAL, not monstrous. The "
          .. "escalation ladder is spread across days so the player lives with it. The takeover is "
          .. "the all-is-lost beat; Vik tapping out is the dark night of the soul; the gig is the "
          .. "false dawn that gets them to Part 4.",
    arms = { arc = 2, daysSincePart = 5, familiarity = 2 },

    beats = {

      { id = "p3_blackout", title = "Ten minutes", kind = "episode",
        intent = "Escalation step one. He loses ten minutes at Misty's and lies about it — and the "
              .. "lie is CHECKABLE, because his own texts have timestamps. This is a thing text "
              .. "can do that voice cannot, and it is the reason the SMS system earns its place "
              .. "twice in this arc.",
        arms = { arc = 2, daysSincePart = 1, atPlace = "misty" },
        place = "misty", window = { 12.0, 21.0 },
        actors = { "jackie", "misty" },
        sms = {
          thread = "jackie", id = "arc_p3_blackout",
          messages = {
            { from = "jackie", text = "at mistys. come by when you're done", stampNote = "14:02" },
            { from = "jackie", text = "you coming or what", stampNote = "14:14 — twelve minutes later, and he has no memory of the first one" },
          },
        },
        vo = { onArrive = "confused", onPressed = "deflect_hard" },
        sets = { [M.FACTS.episodes] = "+1", [M.FACTS.knows_misty] = 1 },
        next = "p3_timestamps",
      },

      { id = "p3_timestamps", title = "The timestamps", kind = "talk",
        intent = "THE PAYOFF OF V'S FLAW. V shows him his own phone to prove he blacked out — and "
              .. "he turns it round: 'You wanna talk about what people don't tell each other?' He "
              .. "has known since the reunion that V lied to him about the Relic. He let it go "
              .. "because he was grateful to be alive. He is not letting it go now.",
        arms = { afterBeat = "p3_blackout" },
        place = "misty", actors = { "jackie" },
        choices = {
          { id = "own_it", text = "You're right. I lied to you. About the Relic, about all of it.",
            outcome = "The only route to the arc's warmest ending. He doesn't forgive V in the "
                   .. "scene — he says 'okay' and changes the subject, and then texts something "
                   .. "kind at 3am, because that is who he is.",
            sets = { [M.FACTS.caught_lie] = 1 },
            familiarity = 4 },
          { id = "deflect", text = "That's not what this is about.",
            outcome = "He lets it drop. It comes back in Part 4 — if V never admitted the lie, "
                   .. "Jackie will not accept V making the decision for him, and the 'you choose' "
                   .. "ending is the only one that plays honestly.",
            sets = { [M.FACTS.caught_lie] = 2 } },
        },
        vo = { open = "deflect_hard", close = "goodbye_soft" },
        next = "p3_discharge",
      },

      { id = "p3_discharge", title = "The shot", kind = "episode",
        intent = "Escalation step two, and the point where this stops being a medical problem and "
              .. "becomes a public-safety one. His hand fires his gun. Nobody is hit. He looks at "
              .. "his own arm like it belongs to someone else, which is the literal truth.",
        arms = { afterBeat = "p3_timestamps", daysSince = 1, following = true, notInCombat = true },
        place = "any", window = { 6.0, 26.0 },
        script = { "one round discharges", "he stares at his hand", "no deflection line this time — silence is the beat" },
        vo = { after = "pain_short" },
        sets = { [M.FACTS.episodes] = "+1" },
        next = "p3_takeover",
      },

      { id = "p3_takeover", title = "Passenger", kind = "episode",
        intent = "The all-is-lost beat. Twenty seconds in which Jackie's chrome uses him, in the "
              .. "back room of his mother's bar, with a nineteen-year-old he has been mentoring in "
              .. "the room. The daemon says nothing — it is not him, and giving it a voice would "
              .. "make it a villain instead of a fault.",
        arms = { afterBeat = "p3_discharge", daysSince = 2, config = "Config.arc.takeover" },
        place = "coyote_back", window = { 20.0, 26.0 },
        actors = { "jackie", "rico" },
        script = {
          "attitude flip to hostile — the shipped mechanic",
          "he raises the gun on Rico (or on nobody, if the side quest was never played)",
          "20s, silent, no VO at all",
          "he drops; attitude restored; heavy pain_bad on the recovery",
        },
        softVariant = {
          note = "SHIPS BEHIND Config.arc.takeover = false — the near-miss version. He gets the "
              .. "gun halfway up and fights it back down. Same information, no violence. The card "
              .. "at the start of the arc tells the player this switch exists.",
        },
        choices = {
          { id = "shoot",   text = "[Shoot his arm]", outcome = "Ends it instantly. He is not angry. That is worse." },
          { id = "tackle",  text = "[Tackle him]",    outcome = "Both of them on the floor of Mama's storeroom." },
          { id = "talk",    text = "Jackie. It's me.", outcome = "Doesn't work. Nothing works. It ends when it ends — and V learning that they cannot talk him out of this is the point of the beat." },
        },
        vo = { after = "pain_bad" },
        sets = { [M.FACTS.episodes] = "+1", [M.FACTS.arc] = 3 },
        next = "p3_vik_taps_out",
      },

      { id = "p3_vik_taps_out", title = "Vik taps out", kind = "shard",
        intent = "The dark night of the soul, delivered as a document because Vik saying it out "
              .. "loud is not something we can record. One sentence in it is the sentence the "
              .. "entire series exists to earn.",
        arms = { afterBeat = "p3_takeover", delayHours = 8 },
        place = "vik",
        shard = {
          id = "arc_vik_taps",
          title = "From Vik — read this alone",
          author = "Viktor Vektor",
          body = {
            "I've had two days with the scan and I'm going to tell you the part I didn't tell him.",
            "",
            "I can trap the daemon, or I can take the chrome out. I can't do both, and I can't do "
              .. "either alone.",
            "",
            "Trapping it means walling it off inside the hardware it's living in. The hardware "
              .. "stays. So does everything it's doing to him, just slower, and he comes to see me "
              .. "every few weeks for the rest of his life.",
            "",
            "Taking it out is cleaner and it's worse. That thing has been running on his neural "
              .. "pattern for fourteen months. It isn't sitting next to him any more. It's using "
              .. "his roads. Pull it and some of him comes with it — and before you ask me how "
              .. "much: I don't know. Nobody knows. There's no literature on this because nobody "
              .. "survives the part where you flatline mid-attack.",
            "",
            "Whatever you do, he needs replacement chrome that Arasaka never touched, and that's "
              .. "not a favour I can do you. That's money.",
            "",
            "One more thing, and then I'll shut up.",
            "",
            "He asked me, when he came round the first time, whether he was still him. I told him "
              .. "yes because he was on my table and it was the only useful thing to say. I've been "
              .. "carrying that answer around for over a year now and I'd like somebody else to "
              .. "have a turn.",
            "",
            "— Vik",
          },
        },
        next = "p3_money",
      },

      { id = "p3_money", title = "One more job", kind = "gig",
        intent = "The false dawn, and the most pointed irony available: the man who quit the merc "
              .. "life takes one more job to pay for getting out of it. Mechanically it is the "
              .. "shipped summon-and-fight loop, which means it is cheap to build and it is the "
              .. "part of the arc that plays most like the mod players already love.",
        arms = { afterBeat = "p3_vik_taps_out" },
        place = "gig_lot", window = { 20.0, 28.0 },
        actors = { "jackie" },
        journal = { quest = "ghost", phase = "p3", objective = "raise_money",
                    text = "Raise €$15,000 for the operation" },
        payout = 15000,
        vo = { onAccept = "money_talk", during = "combat_call", after = "thanks_v" },
        alternatives = {
          note = "The player can also just PAY. If V has €$15,000, the objective can be closed at "
              .. "Vik's counter without the gig. Jackie hates this and says so — being paid for by "
              .. "V is the exact shape of the thing he's afraid of becoming.",
        },
        sets = { [M.FACTS.money] = 1 },
        next = "p3_afraid",
      },

      { id = "p3_afraid", title = "At one remove", kind = "scene",
        intent = "The emotional apex of the arc, and the audit rewrote it for the better. The plan "
              .. "was for Jackie to say he is afraid, out loud, in his own voice. The corpus does "
              .. "not contain the word — not 'afraid', not 'scared', not once in 1101 lines. What "
              .. "it contains instead is this: 'Worried 'bout me. Been for a while.' He can tell "
              .. "you that somebody ELSE is frightened for him. That is the whole of his range, "
              .. "and it is a better scene than the one that was planned, because a man whose "
              .. "defining flaw is that he cannot say things does not get to say the biggest one. "
              .. "So: he talks about Misty being worried. He does not finish the sentence. Then he "
              .. "asks V whether they want another beer.",
        arms = { afterBeat = "p3_money", familiarity = 2, window = { 22.0, 27.0 } },
        place = "coyote", actors = { "jackie" },
        vo = { line = "worried_remove", then_ = "deflect_light" },
        notes = "The actual admission arrives four hours later, in writing, in p3_ask — which is "
             .. "the arc's thesis expressed as a delivery mechanism. Play this beat with NO music "
             .. "cue and no camera work. It is two people at a bar.",
        sets = { [M.FACTS.arc] = 3 },
        next = "p3_ask",
      },

      { id = "p3_ask", title = "The ask", kind = "sms",
        intent = "THE POINT OF NO RETURN, and it arrives as a text at four in the morning, because "
              .. "he cannot ask this out loud. It is also the setup for Part 4's whole structure: "
              .. "the choice is V's only because Jackie handed it over.",
        arms = { afterBeat = "p3_afraid", delayHours = 3, window = { 3.0, 6.0 } },
        sms = {
          thread = "jackie", id = "arc_p3_ask",
          messages = {
            { from = "jackie", text = "vik's got a table free thursday" },
            { from = "jackie", text = "he says it's my call which way we go" },
            { from = "jackie", text = "it isn't though" },
            { from = "jackie", text = "i've been sat here four hours and i can't do it. i keep pickin the one that keeps me useful to you and then i think that's not me thinkin, that's the thing in my head, and then i'm back at the start" },
            { from = "jackie", text = "so you do it" },
            { from = "jackie", text = "whatever you pick i'll sign it. no hard feelins. i mean that" },
            { from = "jackie", text = "thursday. don't be late, chica" },
          },
          replies = {
            { id = "accept", text = "Okay. I'll decide." },
            { id = "refuse", text = "No. This one's yours." },
          },
          followups = {
            accept = { { from = "jackie", text = "thank you" } },
            refuse = { { from = "jackie", text = "…" },
                       { from = "jackie", text = "we'll see thursday" },
                       { from = "jackie", text = "go to sleep" } },
          },
        },
        sets = { [M.FACTS.arc] = 3 },
        next = nil,
      },
    },

    rest = "The operation is funded and booked for Thursday. Jackie has come as close to saying he "
        .. "is frightened as his own recorded voice allows, and then said the rest of it in writing "
        .. "at four in the morning.",
  },

  -- =========================================================================================
  -- PART 4 — "SALVAGE"         the operation.     ACT III: the climax.
  -- =========================================================================================
  {
    id = "p4", title = "Salvage", arcValue = 4,
    logline = "Thursday. Vik's table. Three ways this can go and none of them gives Jackie back.",
    intent = "One room, one choice, permanent consequences. Everything before this exists to make "
          .. "the player unable to pick easily. The design rule: all three endings are "
          .. "defensible, none is the good one, and the mod never tells the player which one it "
          .. "approves of — not in the text, not in the achievement, not in Jackie's face.",
    arms = { arc = 3, beat = "p3_ask" },

    beats = {

      { id = "p4_night_before", title = "Last call", kind = "scene",
        intent = "The pre-battle bonding scene, which is a cliché because it works. Slot the side "
              .. "quest 'Last Call' here if the player hasn't played it. This is the mod's last "
              .. "chance to be warm and it should take it without apologising.",
        arms = { arc = 3, beat = "p3_ask", window = { 21.0, 27.0 } },
        place = "coyote", actors = { "jackie" },
        vo = { open = "lets_go", during = "misty_ref", close = "goodbye_soft" },
        callbacks = {
          "if side_wall done: 'I already got a wall, mano. Don't put me on it twice.'",
          "if side_bike done: he leaves the Arch keys on the bar and doesn't explain why",
          "if knows_mama: she comes down and says nothing at all",
        },
        next = "p4_table",
      },

      { id = "p4_table", title = "Vik's table", kind = "travel",
        intent = "A short walk with a long silence. The objective is trivially easy on purpose — "
              .. "the mod should not ask the player to be good at anything today.",
        arms = { afterBeat = "p4_night_before" },
        place = "vik", window = { 8.0, 14.0 },
        journal = { quest = "ghost", phase = "p4", objective = "the_operation",
                    text = "Be there — Vik's clinic, Thursday morning" },
        next = "p4_choice",
      },

      { id = "p4_choice", title = "The choice", kind = "choice",
        intent = "Four options, three outcomes. The fourth — handing it back — is the arc's thesis "
              .. "and resolves V's arc rather than Jackie's: it is V finally stopping managing "
              .. "him. It is not a secret good ending. It costs the player the ability to control "
              .. "the outcome, and the mod means that.",
        arms = { afterBeat = "p4_table", atPlace = "vik" },
        actors = { "jackie", "vik" },
        choices = {
          { id = "clean", text = "Take it all out.",
            ending = 1, endingName = "Clean",
            outcome = "Everything Arasaka comes out, and the daemon goes with it — and so does "
                   .. "the edge. He is ordinary now.",
            sets = { [M.FACTS.ending] = 1, [M.FACTS.chose_by] = 1 } },
          { id = "caged", text = "Wall it off. Keep the chrome.",
            ending = 2, endingName = "Caged",
            outcome = "The companion the player already knows — with upkeep. Alive, not cured.",
            sets = { [M.FACTS.ending] = 2, [M.FACTS.chose_by] = 1 } },
          { id = "ride", text = "Don't cut. Walk out.",
            ending = 3, endingName = "Ride it",
            outcome = "The strongest Jackie in the mod, on borrowed time, with Arasaka still "
                   .. "coming. This is the ending that Part 2's firefight argued for.",
            sets = { [M.FACTS.ending] = 3, [M.FACTS.chose_by] = 1 } },
          { id = "handback", text = "No. You choose, Jackie.",
            ending = "computed", endingName = "His call",
            outcome = "He is angry for about four seconds and then he goes quiet, and then he "
                   .. "chooses — and what he chooses is read off what the player has actually "
                   .. "taught him about himself.",
            computed = {
              note = "Deterministic, never random. Read in order; first match wins.",
              rules = {
                { when = "caught_lie == 1 and familiarity >= 3", ending = 2,
                  why = "V admitted the lie and he trusts them. He picks the one that keeps him "
                     .. "here, with upkeep, because staying is worth the trouble." },
                { when = "pull_now == 1", ending = 1,
                  why = "He asked to get it all out in Part 1 and was overruled. He has not "
                     .. "changed his mind; he was just waiting to be allowed." },
                { when = "episodes >= 4 or knows_mama == 1", ending = 1,
                  why = "He has seen what he does to the people around him. He picks safety." },
                { when = "familiarity <= 1 or caught_lie == 2", ending = 3,
                  why = "He was never let in far enough to want the quiet life. He goes back to "
                     .. "the only thing he was ever certain he was good at." },
                { fallback = 2 },
              },
            },
            sets = { [M.FACTS.chose_by] = 2 } },
        },
        vo = { close = nil },
        sets = { [M.FACTS.arc] = 4 },
        next = nil,
        notes = "NO LINE PLAYS HERE, and that is the audit's doing: the corpus has no farewell with any\n                 weight in it (see M.CASTING note 2). Jackie says nothing while Vik preps the table.\n                 A borrowed casual \"Ahí luego\" under the biggest moment in the mod would have been\n                 worse than silence, and silence is what a man who cannot say things does anyway.",
      },
    },

    rest = "The operation is over. Which Jackie walks out of it is now a permanent property of "
        .. "this save, and every companion system reads it.",
  },

  -- =========================================================================================
  -- PART 5 — "AFTER"           the epilogue.      Branches on the ending.
  -- =========================================================================================
  {
    id = "p5", title = "After", arcValue = 5,
    logline = "What it is like now — which is a different question in each of the three saves, and "
           .. "the only one the mod has left to answer.",
    intent = "Short. Three of them, one each, and the player only ever sees theirs. An epilogue's "
          .. "job is not to explain the ending — it is to let the player sit in it for ten "
          .. "minutes and find out how they feel.",
    arms = { arc = 4, daysSincePart = 2 },

    beats = {

      { id = "p5a_table", title = "A place at the table", kind = "scene", ending = 1,
        intent = "The warm one, and it is warm because it is small. Mama's dinner, the plate that "
              .. "has been laid every week since he 'died', and the note underneath it that says "
              .. "she knew — which retroactively makes every 'don't tell Mama' in the arc into "
              .. "something sadder and better.",
        place = "coyote", window = { 19.0, 22.0 },
        actors = { "jackie", "mama" },
        shard = {
          id = "arc_mama_note", title = "A note, folded under a plate", author = "Guadalupe Welles",
          body = {
            "Jaquito.",
            "",
            "You think I don't know my own son's hands.",
            "",
            "You have been sitting at my bar for a year with your right hand under the table and "
              .. "your left one doing all the work, and every week I set your plate and every week "
              .. "you tell me you already ate.",
            "",
            "I am not going to ask you what it was. You would lie, and then I would have to decide "
              .. "whether to let you.",
            "",
            "Eat something. You are too thin. Bring your friend.",
            "",
            "— Mamá",
          },
        },
        callbacks = { "if side_card: Misty's card is on the bar next to his plate, face up",
                      "he offers V his bike keys — he doesn't need a bike he can't handle any more" },
        vo = { open = "mama_ref", close = "thanks_v" },
        sets = { [M.FACTS.arc] = 5, [M.FACTS.knows_mama] = 1 },
      },

      { id = "p5b_ritual", title = "Maintenance", kind = "scene", ending = 2,
        intent = "The mod's first ONGOING obligation instead of a completed quest, which suits "
              .. "'alive, not cured' exactly. Every ~10 in-game days he texts that it's flaring; "
              .. "take him to Vik; he's fine for another ten days. It never resolves and it is "
              .. "never a crisis — it is just a thing you do now, like a friend's prescription.",
        place = "vik", window = { 9.0, 20.0 },
        recurring = { everyDays = 10, forever = true },
        sms = {
          thread = "jackie", id = "arc_p5_flare",
          messages = {
            { from = "jackie", text = "it's doin the thing again" },
            { from = "jackie", text = "no rush. thursday's fine" },
            { from = "jackie", text = "bring coffee, viks is terrible" },
          },
        },
        vo = { onArrive = "vik_ref", close = "goodbye_soft" },
        sets = { [M.FACTS.arc] = 5 },
      },

      { id = "p5c_raid", title = "Recovery in progress", kind = "fight", ending = 3,
        intent = "The one earned set-piece in the mod. Arasaka comes to where Jackie sleeps, in "
              .. "force, and he goes back to Rocky Ridge — the garage where V found him in Act I — "
              .. "because it is the only place he ever felt safe. The mod ends where it began, "
              .. "which is not a coincidence and should not be explained to the player.",
        arms = { config = "Config.arc.raid" },
        place = "hideout", window = { 2.0, 6.0 },
        actors = { "jackie", "arasaka_squad", "rico?" },
        spawn = { note = "Three waves. The officer record in wave 3. This is the hardest fight the "
                      .. "mod contains and it is allowed to be." },
        callbacks = {
          "if side_rico: Rico arrives mid-fight with four Valentinos. Nobody asked him to.",
          "if side_bike: the Arch is parked outside, and the escape is on it.",
          "if beacon == 2 (spoofed): they arrive a day earlier — the spoof degraded, exactly as Nix said.",
        },
        vo = { onSpawn = "watched", during = "combat_joy", after = "goodbye_soft" },
        sets = { [M.FACTS.arc] = 5 },
      },
    },

    rest = "Done. Jackie stays in the world as whichever version of himself the player left him.",
  },

  }, -- parts
}

-- ===========================================================================================
-- WHAT ANTONIA HAS TO CAPTURE IN-GAME — the whole ask, in one list.
-- Everything else in this file runs on coordinates the mod already has.
-- ===========================================================================================
M.CAPTURE_LIST = {
  { place = "coyote_back", why = "Part 3's takeover", how = "Back/storeroom area of El Coyote Cojo, facing the door." },
  { place = "mast",        why = "Part 2's jammer plant", how = "A Badlands comms mast with a driveable approach — stand at its base." },
  { place = "wall",        why = "Side quest 'Last Rites'", how = "A memorial wall in Heywood (Vista del Rey has several) — face it." },
  { place = "gig_lot",     why = "Part 3's paying job", how = "An open industrial lot with cover, Santo Domingo, no civilians." },
  note = "Until each is captured the engine falls back to the place named in M.PLACES[x].fallbackKey "
      .. "and writes one line to the log. Nothing breaks; the scene just happens somewhere less good.",
}

return M
