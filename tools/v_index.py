#!/usr/bin/env python3
"""
v_index.py — TURN 12,996 FLAT V LINES INTO SOMETHING YOU CAN ACTUALLY WRITE AGAINST.
=============================================================================

WHY THIS EXISTS
`tools/build_line_library.py` answers "what did this character ever say" — one flat list
of id / text / seconds / addressee, sorted by nothing in particular. That is the right
shape for Jackie (1,101 lines: you can read them all in an afternoon). It is the wrong
shape for **V**, who has 12,996, because the question you actually arrive with is never
"what did V say" — it is:

    "V needs to say hello on a phone call, under two seconds, to Jackie,
     and it has to be a line that works on ANY day of the story."

That query has five axes and the flat library indexes none of them. Every session that
wanted a V line therefore re-derived the same greps from scratch, badly. This file is
that derivation, done once and written down.

WHAT IT ADDS TO EACH LINE
  intents[]   what the line DOES — greet, farewell, checkin, affirm, decline, question,
              thanks, apology, concern, praise, gig, invite, banter, combat, backchannel,
              reassure, refuse_gig, order, exclaim. A line can have several; `primary`
              is the strongest, resolved by INTENT_ORDER.
  mood        warm | amused | cold | angry | sad | urgent | neutral
  channel     phone | inner | cyberspace | radio | world   (from the VO expression — this
              is the one axis you MUST respect: an inner-monologue take plays inside V's
              head with no positioning, and a phone take is EQ'd for a holocall.)
  length      quip (<1.5s) | short (<3s) | medium (<6s) | long
  gendered    True when CDPR recorded different WORDS for male and female V. The audio
              take is the ENGINE's choice and there is only one String ID, so a gendered
              line needs a subtitle that follows V's body gender — see v_gender.lua.
  standalone  the important one. True when the line carries no plot hook: no proper noun
              from the story, no "the Relic", no pronoun pointing at an object that isn't
              on screen. A standalone line can be said on any day, in any save, in any
              order — which is exactly the bar a small-talk pool has to clear, and the
              bar almost nothing in a quest-driven corpus meets.
  blockers[]  when standalone is False, WHY. So a human can overrule it in one glance
              (the classifier is deliberately harsh; "Jackie" is not a blocker when you
              are writing Jackie's mod, and `--to jackie` un-blocks it for you).

HOW TO USE IT (the CLI is the point — the JSON is for tooling, the HTML for browsing)

    python3 tools/v_index.py build              # writes vo_library/v_index.{json,html}

    # the query from the top of this file:
    python3 tools/v_index.py find --intent greet --to jackie --channel phone --max-secs 2

    # what can V say to accept a gig, standalone, no gendered-subtitle work needed?
    python3 tools/v_index.py find --intent affirm --standalone --no-gendered --max-secs 3

    # free-text, still filtered:
    python3 tools/v_index.py find --grep "your mom|familia|abuela" --to jackie

    # what did we already use, and what's left in a bucket?
    python3 tools/v_index.py used                # ids already in config.lua, with text
    python3 tools/v_index.py stats               # the whole shape of the corpus

⚠️  IDS ARE STRINGS. A String ID is ~2e18 and JSON/Lua numbers are doubles; this file
    never int()s one, and neither may you. See vo.lua's header.

⚠️  vo_library/ IS GITIGNORED and v_index.json lands there for the same reason: it is
    CDPR's subtitle text, verbatim. Never commit it, never ship it. Rebuild it in ~100 s.

This tool is persona-agnostic (`--persona jackie` works and is genuinely useful for
finding HIS side of a beat) but every default is tuned for V, who is the one with the
volume problem.
"""

import argparse
import collections
import html
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUTDIR = os.path.join(ROOT, "vo_library")


# ── intent classification ───────────────────────────────────────────────────
#
# Ordered most-specific first: INTENT_ORDER resolves `primary` when a line matches
# several. "Thanks, let's go" is an affirm with a thanks in it, not the other way round,
# because what the line DOES in a tree is move things forward.
#
# These are matched against a lowercased, punctuation-light form of the line. They are
# heuristics and they are wrong sometimes — that is what `find` printing the full text
# is for. Never paste an id without reading its line.

INTENTS = {
    # --- openers ---------------------------------------------------------------
    "greet": [
        r"\bhey\b", r"\bhi\b(?!ll)", r"\bhello\b", r"\byo\b", r"\bhowdy\b",
        r"\bmornin'?\b", r"\bevenin'?\b", r"\bqu[eé] onda\b", r"\bhola\b",
        r"\bwhat'?s up\b", r"\bsup\b", r"\bthere (?:you|ya) are\b",
        r"\blook who\b", r"\blong time\b", r"\bgood to see\b", r"\bnice to see\b",
        r"\bhear me\b", r"\byou there\b", r"\bit'?s me\b", r"\bthis is v\b",
    ],
    # --- closers ---------------------------------------------------------------
    "farewell": [
        r"\bbye\b", r"\blater\b(?!.*\bthan\b)", r"\bsee ya\b", r"\bsee you\b",
        r"\btake care\b", r"\bcatch (?:ya|you)\b", r"\bgotta (?:go|run|bounce|split)\b",
        r"\bi'?m off\b", r"\bhead(?:in')? out\b", r"\bstay safe\b", r"\bbe safe\b",
        r"\bgood ?night\b", r"\bhasta\b", r"\badi[oó]s\b", r"\bnos vemos\b",
        r"\btill next time\b", r"\buntil next\b", r"\bso long\b", r"\bpeace\b",
        r"\bthat'?s (?:it|all)\b", r"\bwe'?re done\b", r"\bi'?ll be in touch\b",
        r"\btalk (?:to you )?later\b", r"\bkeep in touch\b",
    ],
    # --- how are you -----------------------------------------------------------
    "checkin": [
        r"\bhow(?:'?re| are) (?:you|ya|things|you doin)\b", r"\bhow'?s it goin'?\b",
        r"\bhow (?:you )?(?:been|holdin|feelin|doin)\b", r"\byou (?:doin'? )?(?:ok|okay|alright|all right)\b",
        r"\beverything (?:ok|okay|alright|all right)\b", r"\byou good\b",
        r"\bhow'?s (?:your|the) (?:mom|mother|family|ma\b|leg|arm|head|shoulder)\b",
        r"\bc[oó]mo (?:te sientes|est[aá]s)\b", r"\bqu[eé] tal\b",
        r"\bchecking? in\b", r"\bjust checkin'?\b", r"\bwhat'?s new\b",
        r"\bmiss (?:him|her|it|me)\b", r"\bstill (?:kickin|standin|breathin)\b",
        r"\byou alive\b", r"\bgonna be ok\b", r"\byou hurt\b",
    ],
    # --- yes -------------------------------------------------------------------
    "affirm": [
        r"^(?:yeah|yep|yup|sure|ok|okay|right|aight|course|absolutely|definitely)\b",
        r"\bcount me in\b", r"\bi'?m in\b", r"\bwe'?re in\b", r"\blet'?s (?:do|go|move|roll|ride|get)\b",
        r"\bon it\b", r"\bon my way\b", r"\bgot it\b", r"\bunderstood\b", r"\bwill do\b",
        r"\bdo that\b", r"\byou got it\b", r"\bno problem\b", r"\bfine by me\b",
        r"\bsounds (?:good|great|fine|like a plan)\b", r"\bworks for me\b",
        r"\bs[ií],? s[ií]\b", r"\bhere goes\b", r"\bhere we go\b", r"\bready\b",
        r"\bdeal\b", r"\bwhy not\b", r"\bi'?m game\b", r"\bgood\. let'?s\b",
    ],
    # --- no --------------------------------------------------------------------
    "decline": [
        r"^(?:no|nope|nah|nuh)\b", r"\bnot (?:now|today|tonight|this time|interested)\b",
        r"\bcan'?t\b", r"\bforget it\b", r"\bnever ?mind\b", r"\bpass\b",
        r"\banother time\b", r"\brain ?check\b", r"\bmaybe later\b", r"\bnot yet\b",
        r"\bi'?ll pass\b", r"\bno thanks\b", r"\bno need\b", r"\bleave it\b",
        r"\bchanged my mind\b", r"\bdrop it\b", r"\bnot a good time\b",
    ],
    # --- politeness ------------------------------------------------------------
    "thanks": [r"\bthanks\b", r"\bthank you\b", r"\bappreciate\b", r"\bgracias\b",
               r"\bi owe you\b", r"\byou'?re welcome\b", r"\bmuch obliged\b"],
    "apology": [r"\bsorry\b", r"\bmy bad\b", r"\bapolog", r"\bmy fault\b",
                r"\bdidn'?t mean\b", r"\bforgive me\b", r"\blo siento\b"],
    # --- work ------------------------------------------------------------------
    "gig": [
        r"\bgig\b", r"\bjob\b", r"\bwork\b", r"\bcontract\b", r"\bclient\b",
        r"\bfixer\b", r"\beddies\b", r"\bpay(?:s|ing|day)?\b", r"\bmoney\b",
        r"\bscore\b", r"\bheist\b", r"\bcut\b", r"\bsplit\b", r"\bbiz\b",
        r"\bbusiness\b", r"\bmerc\b", r"\bhustle\b",
    ],
    "invite": [
        r"\bcome (?:with|along|on)\b", r"\bjoin me\b", r"\bwanna\b", r"\byou (?:up|down) for\b",
        r"\bgrab a (?:drink|bite|beer)\b", r"\bbuy you a\b", r"\bdinner\b", r"\blunch\b",
        r"\bdrinks?\b", r"\beat\b", r"\bafterlife\b", r"\bmy place\b", r"\bhang out\b",
        r"\bride (?:with|along)\b", r"\bshow you\b", r"\bkeep me company\b",
    ],
    # --- feelings --------------------------------------------------------------
    "concern": [
        r"\bbe careful\b", r"\bwatch (?:out|yourself|your)\b", r"\bworried\b", r"\bworry\b",
        r"\byou sure\b", r"\bsure about (?:that|this)\b", r"\brisky\b", r"\bdangerous\b",
        r"\bdon'?t (?:do|get) (?:anything|yourself)\b", r"\btake it easy\b",
        r"\blook after\b", r"\bstay (?:sharp|frosty|alive)\b", r"\bmind yourself\b",
    ],
    "reassure": [
        r"\bdon'?t worry\b", r"\bit'?s (?:ok|okay|fine|alright|all right)\b",
        r"\bi'?(?:m|ll be) (?:fine|ok|okay|alright)\b", r"\bwe'?ll be (?:fine|ok|okay)\b",
        r"\bno worries\b", r"\bi got (?:this|you|your back)\b", r"\bi'?m here\b",
        r"\btrust me\b", r"\byou can count on me\b", r"\bnothing'?s gonna\b",
    ],
    "praise": [
        r"\bnice (?:one|work|job|shot)\b", r"\bgood (?:job|work|one|call)\b",
        r"\bwell done\b", r"\bimpressive\b", r"\bnot bad\b", r"\bbadass\b",
        r"\byou'?re (?:all right|the best|good)\b", r"\bproud of\b", r"\bbuen trabajo\b",
        r"\bpreem\b", r"\bdelta\b(?! ?force)", r"\byou'?re good\b",
    ],
    "banter": [
        r"\bheh+\b", r"\bhah+a?\b", r"\bfunny\b", r"\bvery funny\b", r"\bkidding\b",
        r"\bjokin'?\b", r"\bsmart ?ass\b", r"\bshut up\b", r"\bcut the\b",
        r"\bshoot the shit\b", r"\bsame old\b", r"\byou'?re somethin'? else\b",
    ],
    # --- combat / urgent -------------------------------------------------------
    "combat": [
        r"\bcover\b", r"\breload", r"\bgrenade\b", r"\bbehind you\b", r"\bflank",
        r"\bhe'?s down\b", r"\bthey'?re down\b", r"\bclear\b", r"\bshoot", r"\bgun\b",
        r"\bincoming\b", r"\bwatch it\b", r"\bgo go go\b", r"\bmove move\b",
        r"\bget down\b", r"\btake (?:him|her|them) out\b", r"\bkill\b", r"\bdead\b",
    ],
    "order": [
        r"\bfollow me\b", r"\bstay (?:here|put|close|back)\b", r"\bwait here\b",
        r"\bgo on\b", r"\bget in\b", r"\blead the way\b", r"\bafter you\b",
        r"\bhold (?:on|up)\b", r"\bgimme a (?:minute|sec|second)\b", r"\bhang on\b",
    ],
    # --- fillers ---------------------------------------------------------------
    "backchannel": [
        r"^(?:mhm+|mm+h*|hm+|uh ?huh|huh|right|riiight|sure|yeah)[.…?!]*$",
        r"^(?:i see|go on|and\?|so\?|then\?|what\?|really\?)[.…?!]*$",
    ],
    "exclaim": [
        r"^(?:fuck|shit|damn|christ|jesus|god ?damn|hell|whoa|woah|ugh|argh|ah)\b",
        r"\bmierda\b", r"\bpendejo\b", r"\bwhat the\b",
    ],
}

# Most-specific → least. `primary` is the first of these the line matched.
INTENT_ORDER = [
    "checkin", "greet", "farewell", "invite", "gig", "affirm", "decline",
    "thanks", "apology", "concern", "reassure", "praise", "order",
    "combat", "banter", "exclaim", "backchannel",
]

# ── mood ────────────────────────────────────────────────────────────────────
MOODS = {
    "amused": [r"\bheh+\b", r"\bhah+a\b", r"\bfunny\b", r"\bjok", r"\bkidding\b", r"\blaugh"],
    "angry": [r"\bfuck (?:you|off|that)\b", r"\bshut (?:up|the)\b", r"\bpissed\b",
              r"\bthe hell\b", r"\bbullshit\b", r"\bgoddamn\b", r"\bsick of\b",
              r"\bhad enough\b", r"\bdon'?t you dare\b"],
    "sad": [r"\bsorry\b", r"\bmiss (?:him|her|you)\b", r"\bgone\b", r"\bdied\b",
            r"\bfuneral\b", r"\bhurts\b", r"\bcan'?t believe\b", r"\bwish (?:i|we|you)\b"],
    "urgent": [r"\bnow\b", r"\bhurry\b", r"\bquick\b", r"\bmove\b", r"\bno time\b",
               r"\bcome on\b", r"\bgo go\b", r"!!"],
    "warm": [r"\bthanks\b", r"\bappreciate\b", r"\bgood to see\b", r"\bmiss(?:ed)? (?:you|ya)\b",
             r"\bproud\b", r"\bglad\b", r"\btake care\b", r"\bmi \w+\b", r"\bfamilia\b",
             r"\blove\b", r"\bfriend\b", r"\bchoom\b", r"\bhermano\b"],
    "cold": [r"\bwhatever\b", r"\bdon'?t care\b", r"\bnot my (?:problem|business)\b",
             r"\byour call\b", r"\bif you say so\b", r"\bnone at all\b"],
}
MOOD_ORDER = ["angry", "sad", "amused", "warm", "urgent", "cold"]

# ── standalone / plot-hook detection ────────────────────────────────────────
#
# A line is `standalone` when it could be said on ANY day of the story, in any save, at
# any point in any order. That is a much higher bar than "it's short", and it is the bar
# a re-usable small-talk or greeting pool has to clear — the failure mode is the mod
# quoting a mission at a player who hasn't played it (or played it three chapters ago).
#
# The classifier is deliberately HARSH and reports its reasons in `blockers`, because a
# false "not reusable" costs one glance and a false "reusable" ships a broken line.

# Story proper nouns. Anything here is a plot hook by construction. Deliberately does
# NOT include "V" (V says her own name constantly) or the mod's own character — `find
# --to <persona>` un-blocks that name for you.
STORY_NOUNS = """
arasaka militech kang tao kangtao biotechnica zetatech netwatch trauma team maelstrom
valentinos tyger claws animals scavs sixth street voodoo boys wraiths barghest
saburo yorinobu hanako takemura goro adam smasher smasher oda jenkins abernathy
dexter deshawn dex evelyn parker woodman fingers judy alvarez panam palmer saul
mitch teddy carol bobby cassidy aldecaldo aldecaldos rogue amendiares kerry eurodyne
johnny silverhand alt cunningham rache bartmoss us cracks samurai
river ward joss randy elizabeth peralez jefferson garry misty olszewski viktor vektor
vik mama welles padre sebastian sandra dorsett stout meredith brigitte placide
maman brigitte netrunner delamain regina jones wakako muamar el capitan dino dinovic
mr hands nix claire russell beat box
relic biochip mikoshi soulkiller blackwall konpeki plaza afterlife lizzie totentanz
clouds megabuilding kabuki watson westbrook pacifica santo domingo heywood
badlands north oak charter hill japantown little china arroyo rancho coronado
dogtown hansen songbird myers reed alex slider
""".split()
# Multi-word entries above are also matched as their component words; that over-triggers
# on "team", "boys", "hands", "claws" etc., so those are pulled back out.
_TOO_COMMON = {"team", "boys", "claws", "hands", "beat", "box", "north", "oak",
               "charter", "hill", "little", "china", "plaza", "cracks", "us", "tao"}
STORY_NOUNS = sorted(set(STORY_NOUNS) - _TOO_COMMON)
STORY_RE = re.compile(r"\b(" + "|".join(map(re.escape, STORY_NOUNS)) + r")\b", re.I)

# A curated noun list can only ever catch the famous ones. The corpus is full of
# one-scene characters — "Later, Spector." / "Take care, Nancy." / "Buh-bye, Brick." —
# and those are worse than an Arasaka reference, because nobody recognises the name as a
# problem while skimming. So any capitalised word that is NOT sentence-initial and NOT a
# word English capitalises anyway is treated as a name. Over-triggers a little (on
# "Night", "God", brand words); that costs one glance, and the blocker names the word so
# the glance is instant. Emitted in the same `names 'x'` shape as STORY_NOUNS, which is
# what lets `--to jackie` forgive Jackie's own name.
CAP_OK = set("""
i i'm i'll i've i'd a the ok okay yeah no yes hey oh ah uh hm mhm well so and but or
mr mrs ms dr sir ma'am god jesus christ damn hell shit fuck night city street
monday tuesday wednesday thursday friday saturday sunday january february march april
may june july august september october november december english spanish japanese
""".split())
CAP_RE = re.compile(r"(?<![.!?…\"']\s)(?<!^)\b([A-Z][a-z']{2,})\b")

# Deixis: the line points at something that has to be on screen or in recent memory.
DEIXIS = [
    (r"\b(?:this|that|these|those|it)\b(?!'?s (?:ok|okay|fine|alright|all right|me|it))",
     "points at something ('this'/'that'/'it') that must already be on screen"),
    (r"\bthe (?:relic|chip|shard|briefcase|body|car|van|door|elevator|building)\b",
     "names a specific prop from a scene"),
    (r"\b(?:he|she|they|him|her|them)\b", "third party who has to have been introduced"),
    (r"\byour (?:brother|sister|dad|father|friend|crew|people|guy|man)\b",
     "assumes a relationship the mod hasn't established"),
]
DEIXIS = [(re.compile(p, re.I), why) for p, why in DEIXIS]

# Lines that are answers to something specific — fine as a REPLY, wrong as an opener.
ANSWER_RE = re.compile(r"^(?:and|but|so|because|'?cause|then|or|yeah,? but|no,? but)\b", re.I)

CHANNEL = {
    "Vo_Expression_Phone": "phone",
    "Vo_Expression_InnerDialog": "inner",
    "Vo_Expression_Cyberspace": "cyberspace",
    "Vo_Experession_Cb_Radio": "radio",   # CDPR's typo, kept verbatim — it is the key
    "": "world",
}


def norm(text):
    """Lowercased, markup-free, apostrophe-normalised — what the regexes see."""
    t = re.sub(r"<[^>]+>", " ", text or "")       # <mothertongue>/<kiroshi> splice markup
    t = t.replace("’", "'").replace("‘", "'")
    t = t.replace("—", " ").replace("–", " ").replace("…", "...")
    return re.sub(r"\s+", " ", t).strip().lower()


def length_bucket(secs):
    if not secs:
        return "unknown"
    if secs < 1.5:
        return "quip"
    if secs < 3.0:
        return "short"
    if secs < 6.0:
        return "medium"
    return "long"


def classify(line):
    """Everything this file adds to one library row."""
    raw = line.get("text") or ""
    t = norm(raw)

    intents = [name for name, pats in INTENTS.items()
               if any(re.search(p, t) for p in pats)]
    primary = next((i for i in INTENT_ORDER if i in intents), "statement")

    mood = next((m for m in MOOD_ORDER
                 if any(re.search(p, t) for p in MOODS[m])), "neutral")

    male = line.get("text_male") or ""
    gendered = bool(male) and norm(male) != t

    blockers = []
    for m in STORY_RE.finditer(raw):
        b = f"names '{m.group(1).lower()}'"
        if b not in blockers:
            blockers.append(b)
    # Mid-sentence capitals = somebody or somewhere with a name. Sentence-initial words
    # are skipped because English capitalises those regardless of what they are.
    plain = re.sub(r"<[^>]+>", " ", raw)
    for sentence in re.split(r"(?<=[.!?…])\s+|\s+[–—-]\s+", plain):
        for word in re.findall(r"[A-Za-z][A-Za-z']*", sentence)[1:]:
            if word[0].isupper() and len(word) > 2 and word.lower() not in CAP_OK:
                b = f"names '{word.lower()}'"
                if b not in blockers:
                    blockers.append(b)
    for pat, why in DEIXIS:
        if pat.search(t) and why not in blockers:
            blockers.append(why)
    if ANSWER_RE.search(t):
        blockers.append("opens mid-thought — it is a reply, not an opener")
    if len(t) > 160:
        blockers.append("too long to drop into a hub")

    return {
        "intents": sorted(intents),
        "primary": primary,
        "mood": mood,
        "channel": CHANNEL.get(line.get("expression") or "", "world"),
        "length": length_bucket(line.get("seconds") or 0),
        "gendered": gendered,
        "standalone": not blockers,
        "blockers": blockers,
    }


def load(persona):
    path = os.path.join(OUTDIR, f"{persona}.json")
    if not os.path.isfile(path):
        sys.exit(f"{path} not found — run:  python3 tools/build_line_library.py build")
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)["lines"]


def build_index(persona):
    rows = []
    for line in load(persona):
        row = dict(line)
        row.update(classify(line))
        rows.append(row)
    return rows


# ── output ──────────────────────────────────────────────────────────────────

def write_json(persona, rows):
    path = os.path.join(OUTDIR, f"{persona}_index.json")
    by_intent = collections.defaultdict(list)
    for r in rows:
        by_intent[r["primary"]].append(r["id"])
    blob = {
        "persona": persona,
        "count": len(rows),
        "note": "CDPR subtitle text — gitignored, never commit or ship. Ids are STRINGS.",
        "by_intent": {k: v for k, v in sorted(by_intent.items())},
        "lines": rows,
    }
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(blob, fh, indent=1)
    return path


CSS = """
body{font:14px/1.5 -apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;margin:0;
background:#12131a;color:#e6e6ee}
header{padding:18px 24px;background:#1b1d28;border-bottom:2px solid #f2d24b;position:sticky;top:0;z-index:9}
h1{margin:0;font-size:19px;color:#f2d24b}
.sub{color:#9a9ab0;font-size:12px;margin-top:4px}
#q{width:100%;max-width:520px;padding:7px 10px;margin-top:10px;background:#0d0e14;
color:#e6e6ee;border:1px solid #3a3d50;border-radius:4px;font-size:13px}
main{padding:0 24px 60px}
h2{color:#f2d24b;font-size:15px;margin:26px 0 6px;border-bottom:1px solid #2a2c3a;padding-bottom:4px}
table{border-collapse:collapse;width:100%}
td{padding:3px 8px;vertical-align:top;border-bottom:1px solid #1e202b}
tr:hover{background:#1a1c26}
.id{font-family:ui-monospace,Menlo,monospace;font-size:11px;color:#6f7fd0;cursor:pointer;white-space:nowrap}
.id:hover{color:#9ab0ff;text-decoration:underline}
.secs{color:#7f8296;font-size:11px;text-align:right;white-space:nowrap}
.tag{display:inline-block;font-size:10px;padding:0 5px;border-radius:3px;margin-right:3px;
background:#2a2c3a;color:#9a9ab0}
.ok{background:#1d3a24;color:#7fd48f}
.g{background:#3a2a1d;color:#d4a87f}
.ph{background:#1d2f3a;color:#7fbdd4}
.txt{color:#e6e6ee}
.m{color:#c9a06a;font-size:12px;display:block}
.bl{color:#6a6c7e;font-size:11px;display:block}
"""

JS = """
const q=document.getElementById('q');
q.addEventListener('input',()=>{
  const s=q.value.toLowerCase();
  document.querySelectorAll('tbody tr').forEach(tr=>{
    tr.style.display = !s || tr.textContent.toLowerCase().includes(s) ? '' : 'none';
  });
  document.querySelectorAll('section').forEach(sec=>{
    const any=[...sec.querySelectorAll('tbody tr')].some(tr=>tr.style.display!=='none');
    sec.style.display=any?'':'none';
  });
});
document.querySelectorAll('.id').forEach(el=>el.addEventListener('click',()=>{
  navigator.clipboard.writeText('jl_'+el.textContent.trim());
  const o=el.textContent;el.textContent='copied!';setTimeout(()=>el.textContent=o,700);
}));
"""


def write_html(persona, rows):
    path = os.path.join(OUTDIR, f"{persona}_index.html")
    groups = collections.defaultdict(list)
    for r in rows:
        groups[r["primary"]].append(r)
    order = [i for i in INTENT_ORDER if i in groups] + \
            [k for k in sorted(groups) if k not in INTENT_ORDER]

    out = [f"<!doctype html><meta charset=utf-8><title>{persona} — line index</title>",
           f"<style>{CSS}</style>",
           "<header>",
           f"<h1>{persona.upper()} — {len(rows)} lines, grouped by what the line DOES</h1>",
           "<div class=sub>Click an id to copy it as <code>jl_&lt;id&gt;</code>. "
           "<b>green</b> = standalone (safe on any day) · <b>orange</b> = gendered subtitle "
           "(needs a v_gender entry) · <b>blue</b> = phone take. "
           "CDPR's text — local reference only, never ship it.</div>",
           "<input id=q placeholder='filter every line — try: mom / gig / phone / choom'>",
           "</header><main>"]

    for g in order:
        rs = sorted(groups[g], key=lambda r: (r.get("seconds") or 99))
        out.append(f"<section><h2>{g} <span class=sub>({len(rs)})</span></h2><table><tbody>")
        for r in rs:
            tags = []
            if r["standalone"]:
                tags.append("<span class='tag ok'>standalone</span>")
            if r["gendered"]:
                tags.append("<span class='tag g'>gendered</span>")
            if r["channel"] != "world":
                tags.append(f"<span class='tag ph'>{r['channel']}</span>")
            if r.get("to"):
                tags.append(f"<span class=tag>to {html.escape(r['to'])}</span>")
            if r["mood"] != "neutral":
                tags.append(f"<span class=tag>{r['mood']}</span>")
            male = ""
            if r["gendered"]:
                male = f"<span class=m>male V: {html.escape(r['text_male'])}</span>"
            bl = ""
            if r["blockers"]:
                bl = f"<span class=bl>{html.escape(' · '.join(r['blockers']))}</span>"
            out.append(
                f"<tr><td class=id>{r['id']}</td>"
                f"<td class=secs>{(r.get('seconds') or 0):.1f}s</td>"
                f"<td class=txt>{html.escape(r['text'])}{male}{''.join(tags)}{bl}</td></tr>")
        out.append("</tbody></table></section>")

    out.append(f"</main><script>{JS}</script>")
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(out))
    return path


# ── commands ────────────────────────────────────────────────────────────────

def cmd_build(args):
    rows = build_index(args.persona)
    j = write_json(args.persona, rows)
    h = write_html(args.persona, rows)
    n_std = sum(1 for r in rows if r["standalone"])
    n_g = sum(1 for r in rows if r["gendered"])
    print(f"{args.persona}: {len(rows)} lines  ({n_std} standalone, {n_g} gendered)")
    print(f"  -> {os.path.relpath(j, ROOT)}")
    print(f"  -> {os.path.relpath(h, ROOT)}   (open this one — it filters as you type)")
    counts = collections.Counter(r["primary"] for r in rows)
    print("  " + "  ".join(f"{k}:{v}" for k, v in counts.most_common()))


def _filter(rows, args):
    out = []
    for r in rows:
        if args.intent and args.intent not in r["intents"] and args.intent != r["primary"]:
            continue
        if args.to is not None:
            # comma-separated, and "-" means "spoken to nobody in particular" — the
            # generic pool, which is where most of the re-usable small talk actually is.
            want = [w.strip().lower() for w in args.to.split(",")]
            have = (r.get("to") or "-").lower()
            if have not in want:
                continue
        if args.channel and r["channel"] != args.channel:
            continue
        if args.mood and r["mood"] != args.mood:
            continue
        if args.length and r["length"] != args.length:
            continue
        if args.max_secs and (r.get("seconds") or 0) > args.max_secs:
            continue
        if args.min_secs and (r.get("seconds") or 0) < args.min_secs:
            continue
        if args.gendered and not r["gendered"]:
            continue
        if args.no_gendered and r["gendered"]:
            continue
        if args.grep and not re.search(args.grep, r["text"], re.I):
            continue
        if args.standalone:
            # `--to X` forgives X's own name: naming Jackie in Jackie's mod is correct.
            bl = [b for b in r["blockers"]
                  if not (args.to and f"names '{args.to.lower()}'" == b.lower())]
            if bl:
                continue
        out.append(r)
    return out


def cmd_find(args):
    rows = _filter(build_index(args.persona), args)
    rows.sort(key=lambda r: (r.get("seconds") or 99))
    print(f"{len(rows)} match\n")
    for r in rows[:args.max]:
        flags = []
        if r["gendered"]:
            flags.append("GENDERED")
        if r["channel"] != "world":
            flags.append(r["channel"].upper())
        if not r["standalone"]:
            flags.append("hooked")
        tail = ("  [" + " ".join(flags) + "]") if flags else ""
        # Printed as a paste-ready Lua row, so the quotes inside CDPR's text (there are
        # plenty — V quotes people constantly) have to be escaped or the paste won't load.
        lua = r["text"].replace("\\", "\\\\").replace('"', '\\"')
        print(f'{{ text = "{lua}", sfx = "jl_{r["id"]}" }},'
              f'  -- {(r.get("seconds") or 0):.1f}s {r["primary"]}/{r["mood"]}'
              f'{" to " + r["to"] if r.get("to") else ""}{tail}')
        if r["gendered"]:
            print(f'    male V: "{r["text_male"]}"')
    if len(rows) > args.max:
        print(f"\n... {len(rows) - args.max} more — raise --max or narrow the filter")


def cmd_stats(args):
    rows = build_index(args.persona)
    def show(title, key):
        c = collections.Counter(
            (r[key] if not isinstance(r[key], list) else "") for r in rows)
        print(f"\n{title}")
        for k, v in c.most_common():
            print(f"  {k or '(none)':16} {v:6}")
    print(f"{args.persona}: {len(rows)} lines")
    show("by intent", "primary")
    show("by mood", "mood")
    show("by channel", "channel")
    show("by length", "length")
    print(f"\nstandalone: {sum(1 for r in rows if r['standalone'])}")
    print(f"gendered:   {sum(1 for r in rows if r['gendered'])}")
    c = collections.Counter(r.get("to") or "(none)" for r in rows)
    print("\nby addressee")
    for k, v in c.most_common(20):
        print(f"  {k:16} {v:6}")


def cmd_used(args):
    """Every id already pasted into the mod, with its line — so nobody re-uses one twice."""
    src = os.path.join(ROOT, "mod", "JackieLives")
    ids = collections.Counter()
    where = collections.defaultdict(set)
    for name in sorted(os.listdir(src)):
        if not name.endswith(".lua"):
            continue
        with open(os.path.join(src, name), encoding="utf-8") as fh:
            for n, ln in enumerate(fh, 1):
                for m in re.finditer(r'jl_(\d{6,})', ln):
                    ids[m.group(1)] += 1
                    where[m.group(1)].add(f"{name}:{n}")
    lib = {r["id"]: r for r in build_index(args.persona)}
    print(f"{len(ids)} distinct ids in mod/JackieLives/*.lua\n")
    for i, n in ids.most_common():
        r = lib.get(i)
        mark = "" if r else "   <-- NOT one of {}'s lines".format(args.persona)
        txt = r["text"] if r else "(not in this persona's library)"
        dup = f"  x{n}" if n > 1 else ""
        print(f'jl_{i}{dup}{mark}\n    {txt}\n    {" ".join(sorted(where[i]))}')


# Keys whose rows are spoken by V, and keys whose rows are spoken by Jackie. Anything else is
# not a line-carrying container and is ignored.
V_KEYS = {"choices", "textPool", "callFarewells"}
J_KEYS = {"jackie", "jackiePool", "arrivalGreetings", "greetings"}


def _owner_scan(path):
    """Yield (lineno, id, owner, caption) for every jl_<id> in config.lua.

    `owner` is 'V' or 'jackie', decided by the nearest ENCLOSING key rather than by the shape
    of the row — a choice row and a pool row look identical once you are three levels deep, and
    guessing from the row is exactly how an id ends up in the wrong mouth.
    """
    stack = []          # (indent, key)
    with open(path, encoding="utf-8") as fh:
        for n, raw in enumerate(fh, 1):
            line = raw.split("--", 1)[0] if raw.lstrip().startswith("--") else raw
            indent = len(raw) - len(raw.lstrip())
            while stack and indent <= stack[-1][0]:
                stack.pop()
            m = re.match(r"\s*(?:Config\.)?(\w+)\s*=\s*\{", raw)
            if m:
                stack.append((indent, m.group(1)))
            sid = re.search(r'sfx = "jl_(\d{6,})"', line)
            if not sid:
                continue
            owner = None
            for _, key in reversed(stack):
                if key in V_KEYS:
                    owner = "V"
                    break
                if key in J_KEYS:
                    owner = "jackie"
                    break
            cap = re.search(r'text = "((?:[^"\\]|\\.)*)"', line)
            yield n, sid.group(1), owner, (cap.group(1).replace('\\"', '"') if cap else None)


def cmd_verify(args):
    """Fail loudly on the three mistakes that are AUDIBLE ONLY.

    1. A V line in Jackie's mouth, or Jackie's in V's. The mod would speak — in the wrong
       voice, from the wrong body. No log shows it; you have to hear it.
    2. A caption that isn't what the recording says. The engine happily draws any subtitle
       over any line, and a paraphrase reads as a desync the moment you hear it.
    3. A gendered line with no vo_gender.lua entry, which mis-captions one of the two Vs.
    """
    cfg = os.path.join(ROOT, "mod", "JackieLives", "config.lua")
    vlib = {r["id"]: r for r in build_index("v")}
    jpath = os.path.join(OUTDIR, "jackie.json")
    with open(jpath, encoding="utf-8") as fh:
        jlib = {l["id"]: l for l in json.load(fh)["lines"]}
    gender = set()
    gpath = os.path.join(ROOT, "mod", "JackieLives", "vo_gender.lua")
    if os.path.isfile(gpath):
        with open(gpath, encoding="utf-8") as fh:
            gender = set(re.findall(r'\["(\d{6,})"\]', fh.read()))

    bad, notes, n = [], [], 0
    for lineno, sid, owner, cap in _owner_scan(cfg):
        if owner is None:
            continue
        n += 1
        in_v, in_j = sid in vlib, sid in jlib
        if owner == "V" and not in_v:
            bad.append(f"config.lua:{lineno}  V says jl_{sid}, which is "
                       f"{'JACKIE' if in_j else 'nobody'}'s line")
        if owner == "jackie" and not in_j:
            bad.append(f"config.lua:{lineno}  Jackie says jl_{sid}, which is "
                       f"{'V' if in_v else 'nobody'}'s line")
        rec = (vlib if owner == "V" else jlib).get(sid)
        if rec and owner == "V" and rec.get("gendered") and sid not in gender:
            bad.append(f"config.lua:{lineno}  jl_{sid} has different male/female WORDS and no "
                       f"vo_gender.lua entry — run tools/gen_vo_gender.py")
        # Caption drift, checked only where the row states its own text on the same line.
        #
        # ⚠️ GRADED, NOT BINARY, AND THAT IS DELIBERATE. Several of Jackie's oldest captions
        # differ from CDPR's by punctuation alone ("can't complain. But we ain't" vs "can't
        # complain, but... we ain't"). Those are NOT worth fixing: translations.lua is keyed on
        # the authored English, so rewriting a comma silently drops nine languages back to
        # English to correct something no player can hear. So near-matches are a note, and only
        # a caption that says something genuinely DIFFERENT fails the build.
        if rec and cap:
            want = re.sub(r"[^a-z0-9 ]", "", norm(rec["text"]))
            got = re.sub(r"[^a-z0-9 ]", "", norm(cap))
            if want and got and want != got:
                import difflib
                ratio = difflib.SequenceMatcher(None, want, got).ratio()
                msg = (f"config.lua:{lineno}  caption drift\n"
                       f"      shown: {cap}\n"
                       f"      CDPR : {rec['text']}")
                (notes if ratio >= 0.85 else bad).append(msg)
    print(f"checked {n} voiced rows in config.lua")
    for b in bad:
        print("  FAIL " + b)
    for w in notes:
        print("  note " + w)
    print(f"\n{len(bad)} problem(s), {len(notes)} cosmetic note(s)")
    sys.exit(1 if bad else 0)


def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--persona", default="v")
    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser("build", help="write vo_library/<persona>_index.{json,html}").set_defaults(fn=cmd_build)
    sub.add_parser("stats", help="the shape of the corpus").set_defaults(fn=cmd_stats)
    sub.add_parser("used", help="ids already used in the mod").set_defaults(fn=cmd_used)
    sub.add_parser("verify", help="fail on wrong-mouth / drifted-caption / ungendered rows"
                   ).set_defaults(fn=cmd_verify)

    f = sub.add_parser("find", help="query the index")
    f.add_argument("--intent", help="|".join(INTENT_ORDER))
    f.add_argument("--to", help="addressee — comma-separated; '-' = spoken to nobody "
                                "in particular (e.g. --to jackie,-)")
    f.add_argument("--channel", choices=["phone", "inner", "cyberspace", "radio", "world"])
    f.add_argument("--mood", choices=MOOD_ORDER + ["neutral"])
    f.add_argument("--length", choices=["quip", "short", "medium", "long"])
    f.add_argument("--max-secs", type=float)
    f.add_argument("--min-secs", type=float)
    f.add_argument("--standalone", action="store_true", help="only plot-free lines")
    f.add_argument("--gendered", action="store_true", help="only lines with different male text")
    f.add_argument("--no-gendered", action="store_true")
    f.add_argument("--grep", help="regex over the text")
    f.add_argument("--max", type=int, default=40)
    f.set_defaults(fn=cmd_find)

    args = p.parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()
